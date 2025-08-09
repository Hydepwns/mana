defmodule ExWire.Sync.SnapshotSupervisor do
  @moduledoc """
  Supervisor for the complete Warp/Snap sync snapshot system.
  
  Manages both SnapshotGenerator (for creating snapshots) and SnapshotServer
  (for serving snapshots to peers). Provides fault tolerance and coordinated
  startup/shutdown of the snapshot serving infrastructure.
  
  ## Child Processes
  
  - **SnapshotGenerator**: Creates snapshots from blockchain state
  - **SnapshotServer**: Serves snapshots to requesting peers
  
  ## Configuration
  
  The supervisor accepts configuration for both child processes:
  
      # Start with custom configuration
      {:ok, sup} = SnapshotSupervisor.start_link([
        serving_enabled: true,
        max_chunk_size: 1024 * 1024,  # 1MB chunks
        compression_level: 6,
        max_concurrent_peers: 50,
        rate_limit_requests_per_minute: 60
      ])
  """
  
  use Supervisor
  require Logger
  
  @name __MODULE__
  
  @doc """
  Start the SnapshotSupervisor with optional configuration.
  """
  @spec start_link(Keyword.t()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: @name)
  end
  
  @doc """
  Get the status of all snapshot system components.
  """
  @spec get_system_status() :: %{
    generator_status: :running | :stopped | :error,
    server_status: :running | :stopped | :error,
    serving_info: map(),
    generation_stats: map()
  }
  def get_system_status() do
    generator_status = case Process.whereis(ExWire.Sync.SnapshotGenerator) do
      nil -> :stopped
      pid when is_pid(pid) -> if Process.alive?(pid), do: :running, else: :error
    end
    
    server_status = case Process.whereis(ExWire.Sync.SnapshotServer) do
      nil -> :stopped  
      pid when is_pid(pid) -> if Process.alive?(pid), do: :running, else: :error
    end
    
    # Get serving info and stats if processes are running
    serving_info = if server_status == :running do
      try do
        ExWire.Sync.SnapshotServer.get_stats()
      rescue
        _ -> %{error: "failed to get server stats"}
      end
    else
      %{error: "server not running"}
    end
    
    generation_stats = if generator_status == :running do
      try do
        ExWire.Sync.SnapshotGenerator.get_stats()
      rescue
        _ -> %{error: "failed to get generator stats"}
      end
    else
      %{error: "generator not running"}
    end
    
    %{
      generator_status: generator_status,
      server_status: server_status,
      serving_info: serving_info,
      generation_stats: generation_stats
    }
  end
  
  @doc """
  Enable or disable snapshot serving for both generator and server.
  """
  @spec set_serving_enabled(boolean()) :: :ok
  def set_serving_enabled(enabled) do
    Logger.info("[SnapshotSupervisor] Setting snapshot serving enabled: #{enabled}")
    
    # Enable/disable on both components
    try do
      ExWire.Sync.SnapshotGenerator.set_serving_enabled(enabled)
    rescue
      error -> Logger.warning("[SnapshotSupervisor] Failed to set generator serving: #{inspect(error)}")
    end
    
    try do
      ExWire.Sync.SnapshotServer.set_serving_enabled(enabled)
    rescue
      error -> Logger.warning("[SnapshotSupervisor] Failed to set server serving: #{inspect(error)}")
    end
    
    :ok
  end
  
  @doc """
  Trigger generation of a new snapshot.
  """
  @spec generate_snapshot(non_neg_integer(), Keyword.t()) :: 
    {:ok, :generating} | {:error, term()}
  def generate_snapshot(block_number, opts \\ []) do
    case Process.whereis(ExWire.Sync.SnapshotGenerator) do
      nil -> 
        {:error, :generator_not_running}
      
      _pid ->
        ExWire.Sync.SnapshotGenerator.generate_snapshot(block_number, opts)
    end
  end
  
  @doc """
  Get comprehensive snapshot system information.
  """
  @spec get_system_info() :: map()
  def get_system_info() do
    status = get_system_status()
    
    # Get additional information if available
    serving_info = if status.server_status == :running do
      try do
        ExWire.Sync.SnapshotServer.get_serving_info()
      rescue
        _ -> %{}
      end
    else
      %{}
    end
    
    available_snapshots = if status.generator_status == :running do
      try do
        ExWire.Sync.SnapshotGenerator.get_serving_info()
      rescue
        _ -> %{snapshots: []}
      end
    else
      %{snapshots: []}
    end
    
    Map.merge(status, %{
      peer_info: Map.get(serving_info, :peer_info, %{}),
      available_snapshots: available_snapshots.snapshots,
      uptime: calculate_uptime()
    })
  end
  
  # Supervisor callbacks
  
  @impl Supervisor
  def init(opts) do
    # Split configuration between generator and server
    generator_opts = Keyword.take(opts, [
      :trie, :serving_enabled, :max_chunk_size, :compression_level
    ])
    
    server_opts = Keyword.take(opts, [
      :serving_enabled, :max_concurrent_peers, :rate_limit_requests_per_minute, :max_bandwidth_mbps
    ])
    
    Logger.info("[SnapshotSupervisor] Starting snapshot system with serving_enabled=#{Keyword.get(opts, :serving_enabled, true)}")
    
    children = [
      # Start SnapshotGenerator first (server depends on it)
      {ExWire.Sync.SnapshotGenerator, generator_opts},
      
      # Start SnapshotServer to serve requests
      {ExWire.Sync.SnapshotServer, server_opts}
    ]
    
    # Use :one_for_one strategy - if generator fails, server should keep running
    # (server will just return empty responses until generator restarts)
    Supervisor.init(children, strategy: :one_for_one, name: @name)
  end
  
  # Private functions
  
  defp calculate_uptime() do
    # Simple uptime calculation based on supervisor start time
    # In a real implementation, this would be more sophisticated
    Process.info(self(), :dictionary)
    |> case do
      {:dictionary, dict} ->
        case Keyword.get(dict, :start_time) do
          nil -> 
            # Store start time if not already stored
            Process.put(:start_time, System.system_time(:second))
            0
          start_time ->
            System.system_time(:second) - start_time
        end
      _ -> 0
    end
  end
end