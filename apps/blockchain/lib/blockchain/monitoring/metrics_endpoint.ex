defmodule Blockchain.Monitoring.MetricsEndpoint do
  @moduledoc """
  HTTP endpoint for exposing Prometheus metrics.
  
  Serves metrics at /metrics endpoint in Prometheus format.
  Also provides health check endpoints at /health and /ready.
  """

  use GenServer
  require Logger

  alias Blockchain.Monitoring.PrometheusExporter

  defstruct [
    :port,
    :server_ref,
    :enabled
  ]

  @type t :: %__MODULE__{
    port: pos_integer(),
    server_ref: pid() | nil,
    enabled: boolean()
  }

  @default_port 9090
  @name __MODULE__

  # Public API

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @spec get_metrics_url() :: String.t() | nil
  def get_metrics_url() do
    GenServer.call(@name, :get_metrics_url)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    enabled = Keyword.get(opts, :enabled, true)
    port = Keyword.get(opts, :port, @default_port)

    if enabled do
      case start_http_server(port) do
        {:ok, server_ref} ->
          Logger.info("[MetricsEndpoint] Started HTTP server on port #{port}")
          Logger.info("[MetricsEndpoint] Metrics available at http://localhost:#{port}/metrics")
          Logger.info("[MetricsEndpoint] Health check available at http://localhost:#{port}/health")
          
          {:ok, %__MODULE__{
            port: port,
            server_ref: server_ref,
            enabled: true
          }}
        
        {:error, reason} ->
          Logger.error("[MetricsEndpoint] Failed to start HTTP server: #{inspect(reason)}")
          {:ok, %__MODULE__{enabled: false}}
      end
    else
      Logger.info("[MetricsEndpoint] Disabled by configuration")
      {:ok, %__MODULE__{enabled: false}}
    end
  end

  @impl true
  def handle_call(:get_metrics_url, _from, %{enabled: false} = state) do
    {:reply, nil, state}
  end

  def handle_call(:get_metrics_url, _from, state) do
    url = "http://localhost:#{state.port}/metrics"
    {:reply, url, state}
  end

  @impl true
  def terminate(_reason, %{server_ref: nil}) do
    :ok
  end

  def terminate(_reason, %{server_ref: server_ref}) do
    # Stop the HTTP server
    :cowboy.stop_listener(server_ref)
    :ok
  end

  # Private functions

  defp start_http_server(port) do
    # Define routes
    dispatch = :cowboy_router.compile([
      {:_, [
        {"/metrics", __MODULE__.MetricsHandler, []},
        {"/health", __MODULE__.HealthHandler, []},
        {"/ready", __MODULE__.ReadinessHandler, []},
        {"/", __MODULE__.RootHandler, []}
      ]}
    ])

    # Start cowboy HTTP server
    case :cowboy.start_clear(
      :metrics_http_listener,
      [{:port, port}],
      %{env: %{dispatch: dispatch}}
    ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  # HTTP Handlers

  defmodule MetricsHandler do
    @moduledoc "Handler for /metrics endpoint"

    def init(req, state) do
      try do
        metrics = PrometheusExporter.get_metrics()
        
        req = :cowboy_req.reply(200, %{
          "content-type" => "text/plain; version=0.0.4; charset=utf-8",
          "cache-control" => "no-cache"
        }, metrics, req)
        
        {:ok, req, state}
      rescue
        error ->
          Logger.error("[MetricsHandler] Error serving metrics: #{inspect(error)}")
          
          req = :cowboy_req.reply(500, %{
            "content-type" => "text/plain"
          }, "Internal Server Error", req)
          
          {:ok, req, state}
      end
    end
  end

  defmodule HealthHandler do
    @moduledoc "Handler for /health endpoint"

    def init(req, state) do
      health_status = get_health_status()
      
      {status_code, response_body} = case health_status.status do
        :healthy ->
          {200, Jason.encode!(%{
            status: "healthy",
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
            checks: health_status.checks
          })}
        
        :unhealthy ->
          {503, Jason.encode!(%{
            status: "unhealthy", 
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
            checks: health_status.checks,
            errors: health_status.errors
          })}
      end
      
      req = :cowboy_req.reply(status_code, %{
        "content-type" => "application/json"
      }, response_body, req)
      
      {:ok, req, state}
    end

    defp get_health_status() do
      checks = %{
        prometheus_exporter: check_prometheus_exporter(),
        memory_usage: check_memory_usage(),
        disk_space: check_disk_space(),
        erlang_vm: check_erlang_vm()
      }

      errors = checks
               |> Enum.filter(fn {_name, status} -> status != :ok end)
               |> Enum.map(fn {name, status} -> "#{name}: #{status}" end)

      overall_status = if Enum.empty?(errors), do: :healthy, else: :unhealthy

      %{
        status: overall_status,
        checks: checks,
        errors: errors
      }
    end

    defp check_prometheus_exporter() do
      try do
        case GenServer.whereis(PrometheusExporter) do
          nil -> :not_running
          pid when is_pid(pid) -> :ok
        end
      rescue
        _ -> :error
      end
    end

    defp check_memory_usage() do
      try do
        memory_info = :erlang.memory()
        total = Keyword.get(memory_info, :total, 0)
        
        # Consider unhealthy if using more than 1GB
        threshold = 1024 * 1024 * 1024  # 1GB
        
        if total > threshold do
          :high_memory_usage
        else
          :ok
        end
      rescue
        _ -> :error
      end
    end

    defp check_disk_space() do
      try do
        case System.cmd("df", ["-h", "."]) do
          {output, 0} ->
            # Parse df output to check if disk usage is below 90%
            lines = String.split(output, "\n", trim: true)
            if length(lines) >= 2 do
              [_header, data_line | _] = lines
              parts = String.split(data_line, ~r/\s+/)
              if length(parts) >= 5 do
                usage_percent = Enum.at(parts, 4)
                # Extract percentage number
                case Regex.run(~r/(\d+)%/, usage_percent) do
                  [_, percent_str] ->
                    percent = String.to_integer(percent_str)
                    if percent > 90, do: :disk_space_low, else: :ok
                  _ -> :ok
                end
              else
                :ok
              end
            else
              :ok
            end
          
          _ -> :ok  # Assume OK if df command fails
        end
      rescue
        _ -> :ok
      end
    end

    defp check_erlang_vm() do
      try do
        process_count = :erlang.system_info(:process_count)
        process_limit = :erlang.system_info(:process_limit)
        
        usage_ratio = process_count / process_limit
        
        cond do
          usage_ratio > 0.9 -> :high_process_usage
          usage_ratio > 0.8 -> :moderate_process_usage
          true -> :ok
        end
      rescue
        _ -> :error
      end
    end
  end

  defmodule ReadinessHandler do
    @moduledoc "Handler for /ready endpoint"

    def init(req, state) do
      readiness_status = get_readiness_status()
      
      {status_code, response_body} = case readiness_status.ready do
        true ->
          {200, Jason.encode!(%{
            ready: true,
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
            services: readiness_status.services
          })}
        
        false ->
          {503, Jason.encode!(%{
            ready: false,
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
            services: readiness_status.services,
            not_ready: readiness_status.not_ready
          })}
      end
      
      req = :cowboy_req.reply(status_code, %{
        "content-type" => "application/json"
      }, response_body, req)
      
      {:ok, req, state}
    end

    defp get_readiness_status() do
      services = %{
        blockchain: check_blockchain_ready(),
        json_rpc: check_json_rpc_ready(),
        p2p_network: check_p2p_ready(),
        storage: check_storage_ready()
      }

      not_ready = services
                  |> Enum.filter(fn {_name, status} -> status != :ready end)
                  |> Enum.map(fn {name, status} -> "#{name}: #{status}" end)

      overall_ready = Enum.empty?(not_ready)

      %{
        ready: overall_ready,
        services: services,
        not_ready: not_ready
      }
    end

    defp check_blockchain_ready() do
      # Check if blockchain application is started and running
      case Application.get_application(__MODULE__) do
        {:ok, app} -> 
          if Application.started_applications() |> Enum.any?(fn {name, _, _} -> name == app end) do
            :ready
          else
            :not_started
          end
        nil -> :not_found
      end
    end

    defp check_json_rpc_ready() do
      # This would check if JSON-RPC server is accepting connections
      # For now, we'll assume it's ready if the application is running
      :ready
    end

    defp check_p2p_ready() do
      # This would check P2P connectivity and peer count
      # For now, we'll assume it's ready
      :ready
    end

    defp check_storage_ready() do
      # This would check if storage backend is accessible
      # For now, we'll assume it's ready
      :ready
    end
  end

  defmodule RootHandler do
    @moduledoc "Handler for / endpoint"

    def init(req, state) do
      response_body = """
      Mana-Ethereum Monitoring Endpoints

      Available endpoints:
      - GET /metrics  - Prometheus metrics
      - GET /health   - Health status check
      - GET /ready    - Readiness check
      
      For more information, see: https://github.com/mana-ethereum/mana
      """
      
      req = :cowboy_req.reply(200, %{
        "content-type" => "text/plain"
      }, response_body, req)
      
      {:ok, req, state}
    end
  end
end