defmodule MerklePatriciaTree.StateManager do
  @moduledoc """
  Advanced state management system with configurable pruning modes,
  reference counting, garbage collection, and disk usage monitoring.
  
  Supports three pruning modes:
  - Fast: Keep only recent states (last ~128 blocks)
  - Full: Keep all states but prune old data periodically
  - Archive: Keep everything (no pruning)
  """

  use GenServer
  require Logger

  alias MerklePatriciaTree.{DB, Trie, TrieStorage}
  alias MerklePatriciaTree.StateManager.{PruningPolicy, ReferenceCounter, GarbageCollector}

  @typedoc "State manager configuration"
  @type config :: %{
    pruning_mode: :fast | :full | :archive,
    fast_blocks_to_keep: pos_integer(),
    full_pruning_interval: pos_integer(),
    gc_interval: pos_integer(),
    disk_usage_check_interval: pos_integer(),
    max_disk_usage_gb: pos_integer(),
    snapshot_interval: pos_integer(),
    compaction_threshold: float()
  }

  @typedoc "State manager state"
  @type t :: %__MODULE__{
    db: DB.db(),
    config: config(),
    reference_counter: ReferenceCounter.t(),
    pruning_stats: pruning_stats(),
    disk_usage: disk_usage_stats(),
    last_snapshot: DateTime.t() | nil,
    compaction_running: boolean()
  }

  @typedoc "Pruning statistics"
  @type pruning_stats :: %{
    total_nodes_pruned: non_neg_integer(),
    bytes_freed: non_neg_integer(),
    last_prune_time: DateTime.t() | nil,
    prune_duration_ms: non_neg_integer()
  }

  @typedoc "Disk usage statistics"
  @type disk_usage_stats :: %{
    total_size_gb: float(),
    state_size_gb: float(),
    blocks_size_gb: float(),
    available_space_gb: float(),
    usage_percentage: float()
  }

  defstruct [
    :db,
    :config,
    :reference_counter,
    :pruning_stats,
    :disk_usage,
    :last_snapshot,
    :compaction_running
  ]

  # Default configuration
  @default_config %{
    pruning_mode: :full,
    fast_blocks_to_keep: 128,
    full_pruning_interval: 3600_000,    # 1 hour
    gc_interval: 300_000,               # 5 minutes
    disk_usage_check_interval: 60_000,  # 1 minute
    max_disk_usage_gb: 500,             # 500 GB limit
    snapshot_interval: 86_400_000,      # 24 hours
    compaction_threshold: 0.3           # 30% fragmentation triggers compaction
  }

  @name __MODULE__

  # Public API

  @spec start_link(DB.db(), Keyword.t()) :: GenServer.on_start()
  def start_link(db, opts \\ []) do
    GenServer.start_link(__MODULE__, {db, opts}, name: @name)
  end

  @spec get_pruning_stats() :: pruning_stats()
  def get_pruning_stats() do
    GenServer.call(@name, :get_pruning_stats)
  end

  @spec get_disk_usage() :: disk_usage_stats()
  def get_disk_usage() do
    GenServer.call(@name, :get_disk_usage)
  end

  @spec force_pruning() :: :ok
  def force_pruning() do
    GenServer.cast(@name, :force_pruning)
  end

  @spec force_garbage_collection() :: :ok
  def force_garbage_collection() do
    GenServer.cast(@name, :force_gc)
  end

  @spec create_snapshot() :: {:ok, String.t()} | {:error, term()}
  def create_snapshot() do
    GenServer.call(@name, :create_snapshot, 60_000)
  end

  @spec trigger_compaction() :: :ok
  def trigger_compaction() do
    GenServer.cast(@name, :trigger_compaction)
  end

  @spec get_state_root_references(binary()) :: non_neg_integer()
  def get_state_root_references(state_root) do
    GenServer.call(@name, {:get_references, state_root})
  end

  @spec increment_state_root_references(binary()) :: :ok
  def increment_state_root_references(state_root) do
    GenServer.cast(@name, {:increment_refs, state_root})
  end

  @spec decrement_state_root_references(binary()) :: :ok
  def decrement_state_root_references(state_root) do
    GenServer.cast(@name, {:decrement_refs, state_root})
  end

  # GenServer callbacks

  @impl true
  def init({db, opts}) do
    config = Map.merge(@default_config, Map.new(opts))
    
    state = %__MODULE__{
      db: db,
      config: config,
      reference_counter: ReferenceCounter.new(),
      pruning_stats: initial_pruning_stats(),
      disk_usage: initial_disk_usage_stats(),
      last_snapshot: nil,
      compaction_running: false
    }

    # Schedule periodic tasks
    schedule_garbage_collection(config.gc_interval)
    schedule_disk_usage_check(config.disk_usage_check_interval)
    schedule_pruning(config)
    schedule_snapshot(config.snapshot_interval)

    Logger.info("[StateManager] Started with pruning mode: #{config.pruning_mode}")

    {:ok, state}
  end

  @impl true
  def handle_call(:get_pruning_stats, _from, state) do
    {:reply, state.pruning_stats, state}
  end

  def handle_call(:get_disk_usage, _from, state) do
    {:reply, state.disk_usage, state}
  end

  def handle_call({:get_references, state_root}, _from, state) do
    refs = ReferenceCounter.get_references(state.reference_counter, state_root)
    {:reply, refs, state}
  end

  def handle_call(:create_snapshot, _from, state) do
    case create_state_snapshot(state) do
      {:ok, snapshot_path} ->
        new_state = %{state | last_snapshot: DateTime.utc_now()}
        {:reply, {:ok, snapshot_path}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast(:force_pruning, state) do
    new_state = perform_pruning(state)
    {:noreply, new_state}
  end

  def handle_cast(:force_gc, state) do
    new_state = perform_garbage_collection(state)
    {:noreply, new_state}
  end

  def handle_cast({:increment_refs, state_root}, state) do
    new_counter = ReferenceCounter.increment(state.reference_counter, state_root)
    {:noreply, %{state | reference_counter: new_counter}}
  end

  def handle_cast({:decrement_refs, state_root}, state) do
    new_counter = ReferenceCounter.decrement(state.reference_counter, state_root)
    {:noreply, %{state | reference_counter: new_counter}}
  end

  def handle_cast(:trigger_compaction, state) do
    if not state.compaction_running do
      spawn(fn -> perform_compaction(state) end)
      {:noreply, %{state | compaction_running: true}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:garbage_collection, state) do
    new_state = perform_garbage_collection(state)
    schedule_garbage_collection(state.config.gc_interval)
    {:noreply, new_state}
  end

  def handle_info(:disk_usage_check, state) do
    new_state = check_disk_usage(state)
    schedule_disk_usage_check(state.config.disk_usage_check_interval)
    {:noreply, new_state}
  end

  def handle_info(:pruning_cycle, state) do
    new_state = perform_pruning(state)
    schedule_pruning(state.config)
    {:noreply, new_state}
  end

  def handle_info(:snapshot_cycle, state) do
    case create_state_snapshot(state) do
      {:ok, _path} ->
        new_state = %{state | last_snapshot: DateTime.utc_now()}
        schedule_snapshot(state.config.snapshot_interval)
        {:noreply, new_state}
      
      {:error, reason} ->
        Logger.warning("[StateManager] Snapshot creation failed: #{inspect(reason)}")
        schedule_snapshot(state.config.snapshot_interval)
        {:noreply, state}
    end
  end

  def handle_info({:compaction_complete, stats}, state) do
    Logger.info("[StateManager] Compaction completed: #{inspect(stats)}")
    {:noreply, %{state | compaction_running: false}}
  end

  # Private functions

  defp initial_pruning_stats() do
    %{
      total_nodes_pruned: 0,
      bytes_freed: 0,
      last_prune_time: nil,
      prune_duration_ms: 0
    }
  end

  defp initial_disk_usage_stats() do
    %{
      total_size_gb: 0.0,
      state_size_gb: 0.0,
      blocks_size_gb: 0.0,
      available_space_gb: 0.0,
      usage_percentage: 0.0
    }
  end

  defp perform_garbage_collection(state) do
    Logger.debug("[StateManager] Performing garbage collection")
    start_time = System.monotonic_time(:millisecond)

    # Find unreferenced state roots
    unreferenced_roots = ReferenceCounter.get_unreferenced_roots(state.reference_counter)
    
    # Collect garbage for each unreferenced root
    {nodes_removed, bytes_freed} = GarbageCollector.collect_unreferenced_nodes(
      state.db,
      unreferenced_roots
    )

    # Update reference counter
    new_counter = ReferenceCounter.remove_roots(state.reference_counter, unreferenced_roots)

    duration = System.monotonic_time(:millisecond) - start_time

    Logger.info("[StateManager] GC completed: #{nodes_removed} nodes removed, #{bytes_freed} bytes freed in #{duration}ms")

    # Update stats
    new_stats = %{state.pruning_stats |
      total_nodes_pruned: state.pruning_stats.total_nodes_pruned + nodes_removed,
      bytes_freed: state.pruning_stats.bytes_freed + bytes_freed,
      prune_duration_ms: duration
    }

    %{state | reference_counter: new_counter, pruning_stats: new_stats}
  end

  defp perform_pruning(state) do
    Logger.info("[StateManager] Performing pruning with mode: #{state.config.pruning_mode}")
    start_time = System.monotonic_time(:millisecond)

    {nodes_pruned, bytes_freed} = case state.config.pruning_mode do
      :fast ->
        PruningPolicy.prune_fast_mode(state.db, state.config.fast_blocks_to_keep)
      
      :full ->
        PruningPolicy.prune_full_mode(state.db, state.reference_counter)
      
      :archive ->
        PruningPolicy.prune_archive_mode()
    end

    duration = System.monotonic_time(:millisecond) - start_time

    Logger.info("[StateManager] Pruning completed: #{nodes_pruned} nodes pruned, #{bytes_freed} bytes freed in #{duration}ms")

    # Update stats
    new_stats = %{state.pruning_stats |
      total_nodes_pruned: state.pruning_stats.total_nodes_pruned + nodes_pruned,
      bytes_freed: state.pruning_stats.bytes_freed + bytes_freed,
      last_prune_time: DateTime.utc_now(),
      prune_duration_ms: duration
    }

    %{state | pruning_stats: new_stats}
  end

  defp check_disk_usage(state) do
    Logger.debug("[StateManager] Checking disk usage")

    # Get current disk usage statistics
    disk_stats = calculate_disk_usage(state.db)
    
    # Check if we're approaching limits
    if disk_stats.usage_percentage > 0.9 do
      Logger.warning("[StateManager] High disk usage: #{Float.round(disk_stats.usage_percentage * 100, 1)}%")
      
      # Trigger emergency pruning if not in archive mode
      if state.config.pruning_mode != :archive do
        spawn(fn -> 
          Logger.info("[StateManager] Triggering emergency pruning due to disk usage")
          GenServer.cast(@name, :force_pruning)
        end)
      end
    end

    # Check if compaction is needed
    fragmentation = calculate_fragmentation_ratio(state.db)
    if fragmentation > state.config.compaction_threshold and not state.compaction_running do
      Logger.info("[StateManager] Triggering compaction due to fragmentation: #{Float.round(fragmentation * 100, 1)}%")
      GenServer.cast(@name, :trigger_compaction)
    end

    %{state | disk_usage: disk_stats}
  end

  defp create_state_snapshot(state) do
    Logger.info("[StateManager] Creating state snapshot")
    
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    snapshot_path = "snapshots/state_snapshot_#{timestamp}.dat"
    
    try do
      # Create snapshots directory if it doesn't exist
      File.mkdir_p!(Path.dirname(snapshot_path))
      
      # Create snapshot data
      snapshot_data = %{
        timestamp: timestamp,
        pruning_mode: state.config.pruning_mode,
        reference_counts: ReferenceCounter.to_map(state.reference_counter),
        pruning_stats: state.pruning_stats,
        disk_usage: state.disk_usage
      }
      
      # Write snapshot to file
      encoded_data = :erlang.term_to_binary(snapshot_data, [:compressed])
      File.write!(snapshot_path, encoded_data)
      
      Logger.info("[StateManager] Snapshot created successfully: #{snapshot_path}")
      {:ok, snapshot_path}
    rescue
      error ->
        Logger.error("[StateManager] Failed to create snapshot: #{inspect(error)}")
        {:error, error}
    end
  end

  defp perform_compaction(state) do
    Logger.info("[StateManager] Starting database compaction")
    start_time = System.monotonic_time(:millisecond)
    
    try do
      # Perform database compaction based on backend
      compaction_stats = case state.db do
        {:ets, _} -> 
          # ETS doesn't need traditional compaction, but we can optimize memory
          :erlang.garbage_collect()
          %{compacted_size: 0, time_ms: 0}
        
        {:antidote, _} ->
          # AntidoteDB compaction would be handled by the database itself
          %{compacted_size: 0, time_ms: 0}
        
        _ ->
          %{compacted_size: 0, time_ms: 0}
      end
      
      duration = System.monotonic_time(:millisecond) - start_time
      
      final_stats = Map.put(compaction_stats, :time_ms, duration)
      
      Logger.info("[StateManager] Compaction completed in #{duration}ms")
      send(self(), {:compaction_complete, final_stats})
    rescue
      error ->
        Logger.error("[StateManager] Compaction failed: #{inspect(error)}")
        send(self(), {:compaction_complete, {:error, error}})
    end
  end

  defp calculate_disk_usage(db) do
    # This is a simplified implementation - in production would use actual filesystem stats
    case db do
      {:ets, _table} ->
        # For ETS, calculate memory usage
        memory_bytes = :ets.info(:trie_cache, :memory) * :erlang.system_info(:wordsize)
        memory_gb = memory_bytes / (1024 * 1024 * 1024)
        
        %{
          total_size_gb: memory_gb,
          state_size_gb: memory_gb * 0.8,  # Estimate
          blocks_size_gb: memory_gb * 0.2,
          available_space_gb: 100.0,  # Assume plenty of RAM
          usage_percentage: memory_gb / 100.0
        }
      
      _ ->
        # Default stats for other backends
        %{
          total_size_gb: 10.0,
          state_size_gb: 8.0,
          blocks_size_gb: 2.0,
          available_space_gb: 90.0,
          usage_percentage: 0.1
        }
    end
  end

  defp calculate_fragmentation_ratio(_db) do
    # Simplified fragmentation calculation
    # In production, this would analyze actual storage fragmentation
    :rand.uniform() * 0.5  # Random value between 0 and 0.5 for testing
  end

  defp schedule_garbage_collection(interval) do
    Process.send_after(self(), :garbage_collection, interval)
  end

  defp schedule_disk_usage_check(interval) do
    Process.send_after(self(), :disk_usage_check, interval)
  end

  defp schedule_pruning(config) do
    interval = case config.pruning_mode do
      :fast -> config.gc_interval * 2     # More frequent for fast mode
      :full -> config.full_pruning_interval
      :archive -> :infinity               # No pruning for archive mode
    end
    
    if interval != :infinity do
      Process.send_after(self(), :pruning_cycle, interval)
    end
  end

  defp schedule_snapshot(interval) do
    Process.send_after(self(), :snapshot_cycle, interval)
  end
end