defmodule ExWire.Eth2.BlobMetrics do
  @moduledoc """
  Metrics collection and monitoring for blob storage operations.
  
  Tracks performance metrics for:
  - Storage operations (latency, throughput, errors)
  - Cache performance (hit rates, evictions)
  - Compression ratios and efficiency
  - Resource utilization
  """

  @doc """
  Initialize metrics collection.
  """
  def init do
    %{
      operations: %{
        store: init_operation_metrics(),
        get: init_operation_metrics(),
        batch_get: init_operation_metrics(),
        cache_hit: init_operation_metrics(),
        cache_miss: init_operation_metrics(),
        not_found: init_operation_metrics()
      },
      compression: %{
        total_uncompressed_bytes: 0,
        total_compressed_bytes: 0,
        compression_operations: 0,
        average_ratio: 0.0
      },
      cache: %{
        total_hits: 0,
        total_misses: 0,
        hit_rate: 0.0,
        evictions: 0
      },
      storage: %{
        total_blobs: 0,
        total_size_bytes: 0,
        disk_usage_bytes: 0,
        memory_usage_bytes: 0
      },
      performance: %{
        average_store_latency_ms: 0.0,
        average_get_latency_ms: 0.0,
        peak_throughput_ops_per_sec: 0.0,
        current_throughput_ops_per_sec: 0.0
      },
      errors: %{
        storage_errors: 0,
        compression_errors: 0,
        cache_errors: 0,
        last_error_timestamp: nil,
        error_rate_per_hour: 0.0
      },
      timestamps: %{
        created_at: System.system_time(:second),
        last_updated: System.system_time(:second),
        last_reset: System.system_time(:second)
      }
    }
  end

  @doc """
  Record a blob operation with timing and performance data.
  """
  def record(metrics, operation, duration_native, value \\ 1.0) do
    duration_ms = System.convert_time_unit(duration_native, :native, :millisecond)
    timestamp = System.system_time(:second)
    
    # Update operation-specific metrics
    operation_metrics = get_in(metrics, [:operations, operation]) || init_operation_metrics()
    updated_operation = update_operation_metrics(operation_metrics, duration_ms, value)
    
    # Update overall performance metrics
    performance = update_performance_metrics(metrics.performance, operation, duration_ms)
    
    # Update cache metrics for cache operations
    cache = update_cache_metrics(metrics.cache, operation)
    
    # Update compression metrics if applicable
    compression = update_compression_metrics(metrics.compression, operation, value)
    
    %{metrics |
      operations: put_in(metrics.operations, [operation], updated_operation),
      performance: performance,
      cache: cache,
      compression: compression,
      timestamps: %{metrics.timestamps | last_updated: timestamp}
    }
  end

  @doc """
  Record an error occurrence.
  """
  def record_error(metrics, error_type, details \\ nil) do
    timestamp = System.system_time(:second)
    
    errors = %{metrics.errors |
      error_rate_per_hour: calculate_error_rate(metrics.errors, timestamp),
      last_error_timestamp: timestamp
    }
    
    errors = case error_type do
      :storage -> %{errors | storage_errors: errors.storage_errors + 1}
      :compression -> %{errors | compression_errors: errors.compression_errors + 1}
      :cache -> %{errors | cache_errors: errors.cache_errors + 1}
      _ -> errors
    end
    
    %{metrics | errors: errors}
  end

  @doc """
  Get current performance statistics.
  """
  def get_stats(metrics) do
    %{
      summary: %{
        total_operations: calculate_total_operations(metrics),
        uptime_seconds: System.system_time(:second) - metrics.timestamps.created_at,
        overall_hit_rate: metrics.cache.hit_rate,
        average_compression_ratio: metrics.compression.average_ratio,
        error_rate: calculate_current_error_rate(metrics)
      },
      performance: metrics.performance,
      cache: metrics.cache,
      compression: format_compression_stats(metrics.compression),
      storage: metrics.storage,
      operations: format_operation_stats(metrics.operations),
      errors: metrics.errors
    }
  end

  @doc """
  Export metrics in Prometheus format.
  """
  def export_prometheus(metrics) do
    timestamp = System.system_time(:millisecond)
    
    [
      # Operation counters
      "blob_operations_total{operation=\"store\"} #{metrics.operations.store.count} #{timestamp}",
      "blob_operations_total{operation=\"get\"} #{metrics.operations.get.count} #{timestamp}",
      "blob_operations_total{operation=\"batch_get\"} #{metrics.operations.batch_get.count} #{timestamp}",
      
      # Latency histograms
      "blob_operation_duration_ms{operation=\"store\",quantile=\"0.5\"} #{metrics.operations.store.p50_ms} #{timestamp}",
      "blob_operation_duration_ms{operation=\"store\",quantile=\"0.95\"} #{metrics.operations.store.p95_ms} #{timestamp}",
      "blob_operation_duration_ms{operation=\"get\",quantile=\"0.5\"} #{metrics.operations.get.p50_ms} #{timestamp}",
      "blob_operation_duration_ms{operation=\"get\",quantile=\"0.95\"} #{metrics.operations.get.p95_ms} #{timestamp}",
      
      # Cache metrics
      "blob_cache_hits_total #{metrics.cache.total_hits} #{timestamp}",
      "blob_cache_misses_total #{metrics.cache.total_misses} #{timestamp}",
      "blob_cache_hit_rate #{metrics.cache.hit_rate} #{timestamp}",
      "blob_cache_evictions_total #{metrics.cache.evictions} #{timestamp}",
      
      # Compression metrics
      "blob_compression_ratio #{metrics.compression.average_ratio} #{timestamp}",
      "blob_compression_savings_bytes #{metrics.compression.total_uncompressed_bytes - metrics.compression.total_compressed_bytes} #{timestamp}",
      
      # Storage metrics
      "blob_storage_size_bytes #{metrics.storage.total_size_bytes} #{timestamp}",
      "blob_storage_count #{metrics.storage.total_blobs} #{timestamp}",
      
      # Error metrics
      "blob_errors_total{type=\"storage\"} #{metrics.errors.storage_errors} #{timestamp}",
      "blob_errors_total{type=\"compression\"} #{metrics.errors.compression_errors} #{timestamp}",
      "blob_errors_total{type=\"cache\"} #{metrics.errors.cache_errors} #{timestamp}"
    ]
    |> Enum.join("\n")
  end

  @doc """
  Reset all metrics to initial state.
  """
  def reset(metrics) do
    %{init() | 
      timestamps: %{
        created_at: metrics.timestamps.created_at,
        last_updated: System.system_time(:second),
        last_reset: System.system_time(:second)
      }
    }
  end

  @doc """
  Update storage metrics with current usage.
  """
  def update_storage_metrics(metrics, total_blobs, total_size_bytes, memory_bytes, disk_bytes \\ 0) do
    storage = %{metrics.storage |
      total_blobs: total_blobs,
      total_size_bytes: total_size_bytes,
      memory_usage_bytes: memory_bytes,
      disk_usage_bytes: disk_bytes
    }
    
    %{metrics | storage: storage}
  end

  # Private Functions

  defp init_operation_metrics do
    %{
      count: 0,
      total_duration_ms: 0.0,
      min_duration_ms: :infinity,
      max_duration_ms: 0.0,
      average_duration_ms: 0.0,
      p50_ms: 0.0,
      p95_ms: 0.0,
      p99_ms: 0.0,
      recent_durations: [],  # Keep last 100 for percentile calculation
      throughput_ops_per_sec: 0.0,
      last_operation_timestamp: nil
    }
  end

  defp update_operation_metrics(metrics, duration_ms, _value) do
    new_count = metrics.count + 1
    new_total = metrics.total_duration_ms + duration_ms
    new_average = new_total / new_count
    
    # Update min/max
    new_min = if duration_ms < metrics.min_duration_ms, do: duration_ms, else: metrics.min_duration_ms
    new_max = if duration_ms > metrics.max_duration_ms, do: duration_ms, else: metrics.max_duration_ms
    
    # Update recent durations for percentile calculation (keep last 100)
    recent_durations = [duration_ms | metrics.recent_durations]
    |> Enum.take(100)
    
    # Calculate percentiles
    {p50, p95, p99} = calculate_percentiles(recent_durations)
    
    # Calculate throughput
    timestamp = System.system_time(:second)
    throughput = calculate_throughput(metrics, timestamp)
    
    %{metrics |
      count: new_count,
      total_duration_ms: new_total,
      min_duration_ms: new_min,
      max_duration_ms: new_max,
      average_duration_ms: new_average,
      p50_ms: p50,
      p95_ms: p95,
      p99_ms: p99,
      recent_durations: recent_durations,
      throughput_ops_per_sec: throughput,
      last_operation_timestamp: timestamp
    }
  end

  defp update_performance_metrics(performance, operation, duration_ms) do
    case operation do
      :store ->
        %{performance | average_store_latency_ms: duration_ms}
      :get ->
        %{performance | average_get_latency_ms: duration_ms}
      _ ->
        performance
    end
  end

  defp update_cache_metrics(cache, operation) do
    case operation do
      :cache_hit ->
        new_hits = cache.total_hits + 1
        total = new_hits + cache.total_misses
        hit_rate = if total > 0, do: new_hits / total, else: 0.0
        
        %{cache |
          total_hits: new_hits,
          hit_rate: hit_rate
        }
        
      :cache_miss ->
        new_misses = cache.total_misses + 1
        total = cache.total_hits + new_misses
        hit_rate = if total > 0, do: cache.total_hits / total, else: 0.0
        
        %{cache |
          total_misses: new_misses,
          hit_rate: hit_rate
        }
        
      _ ->
        cache
    end
  end

  defp update_compression_metrics(compression, operation, value) do
    case operation do
      :store when value > 1.0 ->
        # value is compression ratio
        new_operations = compression.compression_operations + 1
        new_average = (compression.average_ratio * compression.compression_operations + value) / new_operations
        
        %{compression |
          compression_operations: new_operations,
          average_ratio: new_average
        }
        
      _ ->
        compression
    end
  end

  defp calculate_percentiles([]), do: {0.0, 0.0, 0.0}
  defp calculate_percentiles(durations) do
    sorted = Enum.sort(durations)
    count = length(sorted)
    
    p50_index = trunc(count * 0.50)
    p95_index = trunc(count * 0.95)
    p99_index = trunc(count * 0.99)
    
    p50 = Enum.at(sorted, p50_index, 0.0)
    p95 = Enum.at(sorted, p95_index, 0.0)
    p99 = Enum.at(sorted, p99_index, 0.0)
    
    {p50, p95, p99}
  end

  defp calculate_throughput(metrics, current_timestamp) do
    if metrics.last_operation_timestamp do
      time_diff = current_timestamp - metrics.last_operation_timestamp
      if time_diff > 0, do: 1.0 / time_diff, else: 0.0
    else
      0.0
    end
  end

  defp calculate_total_operations(metrics) do
    metrics.operations
    |> Enum.map(fn {_op, data} -> data.count end)
    |> Enum.sum()
  end

  defp calculate_error_rate(errors, current_timestamp) do
    if errors.last_error_timestamp do
      time_diff_hours = (current_timestamp - errors.last_error_timestamp) / 3600.0
      if time_diff_hours > 0 do
        total_errors = errors.storage_errors + errors.compression_errors + errors.cache_errors
        total_errors / time_diff_hours
      else
        0.0
      end
    else
      0.0
    end
  end

  defp calculate_current_error_rate(metrics) do
    total_errors = metrics.errors.storage_errors + metrics.errors.compression_errors + metrics.errors.cache_errors
    total_operations = calculate_total_operations(metrics)
    
    if total_operations > 0, do: total_errors / total_operations, else: 0.0
  end

  defp format_compression_stats(compression) do
    savings_bytes = compression.total_uncompressed_bytes - compression.total_compressed_bytes
    savings_ratio = if compression.total_uncompressed_bytes > 0 do
      savings_bytes / compression.total_uncompressed_bytes
    else
      0.0
    end
    
    %{
      average_ratio: compression.average_ratio,
      total_operations: compression.compression_operations,
      total_uncompressed_bytes: compression.total_uncompressed_bytes,
      total_compressed_bytes: compression.total_compressed_bytes,
      savings_bytes: savings_bytes,
      savings_ratio: savings_ratio
    }
  end

  defp format_operation_stats(operations) do
    operations
    |> Enum.map(fn {op, stats} ->
      {op, %{
        count: stats.count,
        average_latency_ms: stats.average_duration_ms,
        p95_latency_ms: stats.p95_ms,
        throughput_ops_per_sec: stats.throughput_ops_per_sec
      }}
    end)
    |> Enum.into(%{})
  end
end