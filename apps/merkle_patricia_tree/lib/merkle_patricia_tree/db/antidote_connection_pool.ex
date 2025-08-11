defmodule MerklePatriciaTree.DB.AntidoteConnectionPool do
  @moduledoc """
  Connection pool manager for AntidoteDB connections.

  Provides:
  - Connection pooling with configurable size
  - Automatic connection recovery
  - Load balancing across multiple nodes
  - Circuit breaker pattern for fault tolerance
  - Health checking and monitoring
  """

  use GenServer
  require Logger

  @type connection :: :gen_tcp.socket()
  @type pool_state :: %{
          nodes: list({String.t(), non_neg_integer()}),
          connections: list({connection(), :available | :busy}),
          pool_size: non_neg_integer(),
          health_check_interval: non_neg_integer(),
          circuit_breaker: map()
        }

  # Configuration
  @default_pool_size 10
  # 30 seconds
  @default_health_check_interval 30_000
  @connection_timeout 5_000
  # @max_retries 3
  # @retry_delay 1_000

  # Circuit breaker settings
  # failures before opening
  @circuit_breaker_threshold 5
  # time before half-open state
  @circuit_breaker_timeout 60_000

  ## Client API

  @doc """
  Starts the connection pool.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets a connection from the pool.
  """
  def checkout(timeout \\ 5000) do
    GenServer.call(__MODULE__, :checkout, timeout)
  end

  @doc """
  Returns a connection to the pool.
  """
  def checkin(conn) do
    GenServer.cast(__MODULE__, {:checkin, conn})
  end

  @doc """
  Executes a function with a pooled connection.
  """
  def with_connection(fun, timeout \\ 5000) do
    case checkout(timeout) do
      {:ok, conn} ->
        try do
          result = fun.(conn)
          checkin(conn)
          result
        rescue
          e ->
            checkin(conn)
            reraise e, __STACKTRACE__
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the current pool status.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Starts a connection pool with the given configuration.
  """
  def start_pool(pool_name, opts \\ []) do
    # For now, delegate to start_link with a name
    name = {:via, Registry, {MerklePatriciaTree.Registry, {__MODULE__, pool_name}}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Stops a connection pool.
  """
  def stop_pool(pool_name) do
    name = {:via, Registry, {MerklePatriciaTree.Registry, {__MODULE__, pool_name}}}
    GenServer.stop(name)
  end

  @doc """
  Performs a read operation using the connection pool.
  """
  def read(key, opts \\ []) do
    with_connection(fn conn ->
      MerklePatriciaTree.DB.AntidoteClient.get(conn, opts[:bucket] || "default", key)
    end)
  end

  @doc """
  Performs a write operation using the connection pool.
  """
  def write(key, value, opts \\ []) do
    with_connection(fn conn ->
      MerklePatriciaTree.DB.AntidoteClient.put!(conn, opts[:bucket] || "default", key, value)
    end)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    nodes = Keyword.get(opts, :nodes, [{"localhost", 8087}])
    pool_size = Keyword.get(opts, :pool_size, @default_pool_size)

    health_check_interval =
      Keyword.get(opts, :health_check_interval, @default_health_check_interval)

    state = %{
      nodes: nodes,
      connections: [],
      pool_size: pool_size,
      health_check_interval: health_check_interval,
      circuit_breaker: initialize_circuit_breakers(nodes)
    }

    # Start health check timer
    Process.send_after(self(), :health_check, health_check_interval)

    # Initialize connections
    send(self(), :initialize_pool)

    {:ok, state}
  end

  @impl true
  def handle_call(:checkout, _from, state) do
    case find_available_connection(state.connections) do
      {conn, remaining} ->
        new_connections = [{conn, :busy} | remaining]
        {:reply, {:ok, conn}, %{state | connections: new_connections}}

      nil ->
        # Try to create a new connection if under pool size
        if length(state.connections) < state.pool_size do
          case create_connection(state.nodes, state.circuit_breaker) do
            {:ok, conn} ->
              new_connections = [{conn, :busy} | state.connections]
              {:reply, {:ok, conn}, %{state | connections: new_connections}}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        else
          # Queue the request or timeout
          {:reply, {:error, :pool_exhausted}, state}
        end
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      total_connections: length(state.connections),
      available: Enum.count(state.connections, fn {_, status} -> status == :available end),
      busy: Enum.count(state.connections, fn {_, status} -> status == :busy end),
      nodes: state.nodes,
      circuit_breaker: state.circuit_breaker
    }

    {:reply, status, state}
  end

  @impl true
  def handle_cast({:checkin, conn}, state) do
    new_connections = update_connection_status(state.connections, conn, :available)
    {:noreply, %{state | connections: new_connections}}
  end

  @impl true
  def handle_info(:initialize_pool, state) do
    connections = initialize_connections(state.nodes, state.pool_size, state.circuit_breaker)
    {:noreply, %{state | connections: connections}}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Check health of all connections
    new_connections = check_connections_health(state.connections)

    # Update circuit breakers based on health
    new_circuit_breaker =
      update_circuit_breakers(state.nodes, new_connections, state.circuit_breaker)

    # Schedule next health check
    Process.send_after(self(), :health_check, state.health_check_interval)

    {:noreply, %{state | connections: new_connections, circuit_breaker: new_circuit_breaker}}
  end

  ## Private Functions

  defp initialize_circuit_breakers(nodes) do
    Map.new(nodes, fn {host, port} ->
      {{host, port},
       %{
         state: :closed,
         failures: 0,
         last_failure: nil,
         success_count: 0
       }}
    end)
  end

  defp initialize_connections(nodes, pool_size, circuit_breaker) do
    connections_per_node = div(pool_size, length(nodes))

    Enum.flat_map(nodes, fn {host, port} ->
      case Map.get(circuit_breaker, {host, port}) do
        %{state: :open} ->
          # Skip nodes with open circuit
          []

        _ ->
          1..connections_per_node
          |> Enum.map(fn _ ->
            case create_single_connection(host, port) do
              {:ok, conn} -> {conn, :available}
              {:error, _} -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)
      end
    end)
  end

  defp create_connection(nodes, circuit_breaker) do
    available_nodes =
      Enum.filter(nodes, fn {host, port} ->
        case Map.get(circuit_breaker, {host, port}) do
          %{state: :open} -> false
          _ -> true
        end
      end)

    case available_nodes do
      [] ->
        {:error, :no_available_nodes}

      nodes ->
        {host, port} = Enum.random(nodes)
        create_single_connection(host, port)
    end
  end

  defp create_single_connection(host, port) do
    case :gen_tcp.connect(
           String.to_charlist(host),
           port,
           [:binary, {:packet, 0}, {:active, false}],
           @connection_timeout
         ) do
      {:ok, socket} ->
        Logger.debug("Connected to AntidoteDB at #{host}:#{port}")
        {:ok, socket}

      {:error, reason} ->
        Logger.warning("Failed to connect to AntidoteDB at #{host}:#{port}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp find_available_connection(connections) do
    case Enum.split_with(connections, fn {_, status} -> status == :available end) do
      {[], _} ->
        nil

      {[{conn, :available} | rest_available], busy} ->
        {conn, rest_available ++ busy}
    end
  end

  defp update_connection_status(connections, conn, new_status) do
    Enum.map(connections, fn
      {^conn, _} -> {conn, new_status}
      other -> other
    end)
  end

  defp check_connections_health(connections) do
    Enum.map(connections, fn {conn, status} ->
      if connection_alive?(conn) do
        {conn, status}
      else
        :gen_tcp.close(conn)
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp connection_alive?(conn) do
    # Send ping
    case :gen_tcp.send(conn, <<0>>) do
      :ok -> true
      {:error, _} -> false
    end
  end

  defp update_circuit_breakers(nodes, connections, circuit_breaker) do
    # Update circuit breaker state based on connection health
    Map.new(nodes, fn {_host, _port} = node ->
      current_breaker = Map.get(circuit_breaker, node)

      # Count successful connections to this node
      success_count =
        Enum.count(connections, fn {conn, _} ->
          # Check if connection belongs to this node (simplified check)
          connection_alive?(conn)
        end)

      new_breaker =
        case current_breaker.state do
          :closed when success_count == 0 ->
            # Increment failure count
            failures = current_breaker.failures + 1

            if failures >= @circuit_breaker_threshold do
              %{
                current_breaker
                | state: :open,
                  failures: failures,
                  last_failure: System.system_time(:millisecond)
              }
            else
              %{current_breaker | failures: failures}
            end

          :open ->
            # Check if timeout has passed
            now = System.system_time(:millisecond)

            if now - current_breaker.last_failure > @circuit_breaker_timeout do
              %{current_breaker | state: :half_open}
            else
              current_breaker
            end

          :half_open when success_count > 0 ->
            # Success in half-open state, close the circuit
            %{current_breaker | state: :closed, failures: 0, success_count: success_count}

          :half_open ->
            # Failure in half-open state, reopen
            %{current_breaker | state: :open, last_failure: System.system_time(:millisecond)}

          _ ->
            current_breaker
        end

      {node, new_breaker}
    end)
  end
end
