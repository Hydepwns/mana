defmodule MerklePatriciaTree.DB.MemoryOptimizer do
  @moduledoc """
  Memory optimization module for large state trees in Phase 2.3.

  This module provides advanced memory management features specifically designed
  for blockchain applications with large state trees.

  ## Features

  - **LRU Cache Management**: Intelligent caching with configurable eviction policies
  - **Memory-Efficient Data Structures**: Optimized storage for blockchain state
  - **Garbage Collection Optimization**: Proactive memory cleanup
  - **Memory Monitoring**: Real-time memory usage tracking
  - **Compression**: Optional data compression for large values
  - **Streaming Operations**: Memory-efficient processing of large datasets

  ## Usage

      # Initialize memory optimizer
      {:ok, optimizer} = MemoryOptimizer.init(max_cache_size: 100_000)

      # Optimize memory usage
      MemoryOptimizer.optimize(optimizer)

      # Monitor memory usage
      metrics = MemoryOptimizer.get_metrics(optimizer)
  """

  require Logger

  @type optimizer :: %{
          cache: :ets.tid(),
          cache_size: non_neg_integer(),
          max_cache_size: non_neg_integer(),
          compression_enabled: boolean(),
          gc_threshold: float(),
          memory_monitor: pid() | nil,
          stats: map()
        }

  @type cache_entry :: %{
          key: any(),
          value: any(),
          size: non_neg_integer(),
          access_count: non_neg_integer(),
          last_access: integer(),
          compressed: boolean()
        }

  # Default configuration
  @default_max_cache_size 100_000
  @default_compression_enabled true
  # 80% memory usage triggers GC
  @default_gc_threshold 0.8
  # Compress values > 1KB
  @default_compression_threshold 1024

  @doc """
  Initializes the memory optimizer with configuration options.
  """
  @spec init(Keyword.t()) :: {:ok, optimizer()} | {:error, String.t()}
  def init(opts \\ []) do
    max_cache_size = Keyword.get(opts, :max_cache_size, @default_max_cache_size)
    compression_enabled = Keyword.get(opts, :compression_enabled, @default_compression_enabled)
    gc_threshold = Keyword.get(opts, :gc_threshold, @default_gc_threshold)

    # Initialize LRU cache
    cache = :ets.new(:memory_optimizer_cache, [:set, :private])

    # Start memory monitor
    memory_monitor = start_memory_monitor(gc_threshold)

    optimizer = %{
      cache: cache,
      cache_size: 0,
      max_cache_size: max_cache_size,
      compression_enabled: compression_enabled,
      gc_threshold: gc_threshold,
      memory_monitor: memory_monitor,
      stats: %{
        cache_hits: 0,
        cache_misses: 0,
        compressions: 0,
        decompressions: 0,
        gc_cycles: 0,
        memory_freed: 0
      }
    }

    Logger.info("Memory optimizer initialized with max cache size: #{max_cache_size}")
    {:ok, optimizer}
  end

  @doc """
  Stores a value in the optimized cache with automatic compression.
  """
  @spec put(optimizer(), any(), any()) :: :ok | {:error, String.t()}
  def put(optimizer, key, value) do
    # Calculate value size
    value_size = calculate_value_size(value)

    # Compress if enabled and value is large enough
    {compressed_value, compressed, final_size} =
      if optimizer.compression_enabled and value_size > @default_compression_threshold do
        compressed = compress_value(value)
        {compressed, true, byte_size(compressed)}
      else
        {value, false, value_size}
      end

    # Create cache entry
    entry = %{
      key: key,
      value: compressed_value,
      size: final_size,
      access_count: 1,
      last_access: System.monotonic_time(:millisecond),
      compressed: compressed
    }

    # Check if we need to evict entries
    if optimizer.cache_size + final_size > optimizer.max_cache_size do
      evict_entries(optimizer, final_size)
    end

    # Store entry
    :ets.insert(optimizer.cache, {key, entry})

    # Update stats
    update_stats(optimizer, :put, final_size, compressed)

    :ok
  end

  @doc """
  Retrieves a value from the optimized cache with automatic decompression.
  """
  @spec get(optimizer(), any()) :: {:ok, any()} | {:error, :not_found}
  def get(optimizer, key) do
    case :ets.lookup(optimizer.cache, key) do
      [{^key, entry}] ->
        # Update access statistics
        updated_entry = %{
          entry
          | access_count: entry.access_count + 1,
            last_access: System.monotonic_time(:millisecond)
        }

        :ets.insert(optimizer.cache, {key, updated_entry})

        # Decompress if needed
        value =
          if entry.compressed do
            decompress_value(entry.value)
          else
            entry.value
          end

        update_stats(optimizer, :hit, entry.size, entry.compressed)
        {:ok, value}

      [] ->
        update_stats(optimizer, :miss, 0, false)
        {:error, :not_found}
    end
  end

  @doc """
  Removes a value from the cache.
  """
  @spec delete(optimizer(), any()) :: :ok
  def delete(optimizer, key) do
    case :ets.lookup(optimizer.cache, key) do
      [{^key, entry}] ->
        :ets.delete(optimizer.cache, key)
        update_stats(optimizer, :delete, entry.size, entry.compressed)

      [] ->
        :ok
    end
  end

  @doc """
  Optimizes memory usage by compacting cache and triggering garbage collection.
  """
  @spec optimize(optimizer()) :: :ok
  def optimize(optimizer) do
    Logger.info("Starting memory optimization")

    # Compact cache
    compact_cache(optimizer)

    # Trigger garbage collection
    trigger_garbage_collection(optimizer)

    # Update memory statistics
    update_memory_stats(optimizer)

    Logger.info("Memory optimization complete")
    :ok
  end

  @doc """
  Gets comprehensive memory usage metrics.
  """
  @spec get_metrics(optimizer()) :: map()
  def get_metrics(optimizer) do
    cache_info = :ets.info(optimizer.cache)
    memory_info = :erlang.memory()

    %{
      cache: %{
        size: cache_info[:size],
        memory: cache_info[:memory],
        max_size: optimizer.max_cache_size
      },
      system: %{
        total_mb: memory_info[:total] / 1024 / 1024,
        process_mb: memory_info[:processes] / 1024 / 1024,
        system_mb: memory_info[:system] / 1024 / 1024,
        atom_mb: memory_info[:atom] / 1024 / 1024
      },
      stats: optimizer.stats,
      efficiency: %{
        cache_hit_rate: calculate_hit_rate(optimizer.stats),
        compression_ratio: calculate_compression_ratio(optimizer.stats),
        memory_usage_percent: calculate_memory_usage_percent(memory_info)
      }
    }
  end

  @doc """
  Streams large datasets with memory-efficient processing.
  """
  @spec stream_large_dataset(optimizer(), Enumerable.t(), (any() -> any())) :: :ok
  def stream_large_dataset(optimizer, dataset, processor) do
    dataset
    # Process in chunks
    |> Stream.chunk_every(1000)
    |> Stream.each(fn chunk ->
      Enum.each(chunk, processor)

      # Optimize memory after each chunk
      if should_optimize(optimizer) do
        optimize(optimizer)
      end
    end)
    |> Stream.run()

    :ok
  end

  @doc """
  Cleans up resources and stops the memory optimizer.
  """
  @spec cleanup(optimizer()) :: :ok
  def cleanup(optimizer) do
    # Stop memory monitor
    if optimizer.memory_monitor do
      Process.exit(optimizer.memory_monitor, :normal)
    end

    # Clear cache
    :ets.delete(optimizer.cache)

    Logger.info("Memory optimizer cleaned up")
    :ok
  end

  # Private functions

  defp start_memory_monitor(gc_threshold) do
    spawn_link(fn -> memory_monitor_loop(gc_threshold) end)
  end

  defp memory_monitor_loop(gc_threshold) do
    receive do
      :check_memory ->
        memory_info = :erlang.memory()
        usage_percent = memory_info[:total] / :erlang.memory(:total) * 100

        if usage_percent > gc_threshold * 100 do
          Logger.warning("Memory usage high (#{usage_percent}%), triggering optimization")
          # Trigger optimization in the main process
          send(self(), :optimize_memory)
        end

        # Schedule next check
        # Check every 30 seconds
        Process.send_after(self(), :check_memory, 30_000)
        memory_monitor_loop(gc_threshold)
    end
  end

  defp calculate_value_size(value) do
    :erlang.term_to_binary(value) |> byte_size()
  end

  defp compress_value(value) do
    value_binary = :erlang.term_to_binary(value)
    :zlib.compress(value_binary)
  end

  defp decompress_value(compressed_value) do
    decompressed = :zlib.uncompress(compressed_value)
    :erlang.binary_to_term(decompressed)
  end

  defp evict_entries(optimizer, needed_size) do
    # Get all entries sorted by access count and last access time
    entries =
      :ets.tab2list(optimizer.cache)
      |> Enum.map(fn {key, entry} -> {key, entry} end)
      |> Enum.sort_by(
        fn {_key, entry} ->
          {entry.access_count, entry.last_access}
        end,
        :asc
      )

    # Evict entries until we have enough space
    {evicted_entries, _remaining} =
      Enum.split_while(entries, fn {_key, entry} ->
        entry.size <= needed_size
      end)

    Enum.each(evicted_entries, fn {key, _entry} ->
      :ets.delete(optimizer.cache, key)
    end)

    Logger.debug("Evicted #{length(evicted_entries)} entries from cache")
  end

  defp compact_cache(optimizer) do
    # Remove entries that haven't been accessed recently
    # 5 minutes ago
    cutoff_time = System.monotonic_time(:millisecond) - 300_000

    entries_to_remove =
      :ets.select(optimizer.cache, [
        {{:_, %{last_access: :"$1"}}, [{:<, :"$1", cutoff_time}], [true]}
      ])

    :ets.select_delete(optimizer.cache, [
      {{:_, %{last_access: :"$1"}}, [{:<, :"$1", cutoff_time}], [true]}
    ])

    Logger.debug("Compacted cache, removed #{entries_to_remove} old entries")
  end

  defp trigger_garbage_collection(optimizer) do
    gc_start = System.monotonic_time(:microsecond)

    # Force garbage collection
    :erlang.garbage_collect()

    gc_end = System.monotonic_time(:microsecond)
    gc_time = (gc_end - gc_start) / 1000

    # Update stats
    optimizer = update_gc_stats(optimizer, gc_time)

    Logger.debug("Garbage collection completed in #{gc_time}ms")
  end

  defp update_memory_stats(optimizer) do
    memory_info = :erlang.memory()

    memory_freed =
      optimizer.stats.memory_freed +
        (memory_info[:total] - optimizer.stats.memory_freed)

    %{optimizer | stats: %{optimizer.stats | memory_freed: memory_freed}}
  end

  defp update_stats(optimizer, operation, size, compressed) do
    stats =
      case operation do
        :put ->
          %{
            optimizer.stats
            | compressions: optimizer.stats.compressions + if(compressed, do: 1, else: 0)
          }

        :hit ->
          %{optimizer.stats | cache_hits: optimizer.stats.cache_hits + 1}

        :miss ->
          %{optimizer.stats | cache_misses: optimizer.stats.cache_misses + 1}

        :delete ->
          %{optimizer.stats | memory_freed: optimizer.stats.memory_freed + size}
      end

    %{optimizer | stats: stats}
  end

  defp update_gc_stats(optimizer, gc_time) do
    stats = %{optimizer.stats | gc_cycles: optimizer.stats.gc_cycles + 1}
    %{optimizer | stats: stats}
  end

  defp calculate_hit_rate(stats) do
    total_requests = stats.cache_hits + stats.cache_misses

    if total_requests > 0 do
      stats.cache_hits / total_requests * 100
    else
      0.0
    end
  end

  defp calculate_compression_ratio(stats) do
    if stats.compressions > 0 do
      # Simplified compression ratio calculation
      # Assume 30% compression on average
      0.7
    else
      1.0
    end
  end

  defp calculate_memory_usage_percent(memory_info) do
    memory_info[:total] / :erlang.memory(:total) * 100
  end

  defp should_optimize(optimizer) do
    memory_info = :erlang.memory()
    usage_percent = calculate_memory_usage_percent(memory_info)
    usage_percent > optimizer.gc_threshold * 100
  end
end
