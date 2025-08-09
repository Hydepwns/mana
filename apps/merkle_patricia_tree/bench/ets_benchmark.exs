#!/usr/bin/env elixir

# ETS Backend Performance Benchmark
# Establishes baseline performance metrics for comparison with AntidoteDB

defmodule ETSBenchmark do
  @moduledoc """
  Performance benchmarking for ETS backend.
  Provides baseline metrics for comparison.
  """

  def run_all_tests do
    IO.puts("\n🚀 ETS Backend Performance Benchmark")
    IO.puts("=" |> String.duplicate(60))
    
    # Run benchmarks
    single_ops_results = benchmark_single_operations()
    batch_ops_results = benchmark_batch_operations()
    concurrent_results = benchmark_concurrent_operations()
    
    # Display summary
    display_summary(single_ops_results, batch_ops_results, concurrent_results)
  end

  def benchmark_single_operations do
    IO.puts("\n📊 Single Operations (10,000 operations)")
    IO.puts("-" |> String.duplicate(40))
    
    # Initialize ETS
    {_, ets_ref} = MerklePatriciaTree.DB.ETS.init(:benchmark_ets)
    
    # Test data
    test_data = for i <- 1..10_000, do: {"key_#{i}", "value_#{i}_#{:rand.uniform(1000)}"}
    
    # Write benchmark
    write_start = System.monotonic_time(:microsecond)
    Enum.each(test_data, fn {key, value} ->
      MerklePatriciaTree.DB.ETS.put!(ets_ref, key, value)
    end)
    write_time = System.monotonic_time(:microsecond) - write_start
    write_ops_per_sec = 10_000 * 1_000_000 / write_time
    
    IO.puts("  Write: #{format_number(write_ops_per_sec)} ops/sec (#{write_time} μs total)")
    
    # Read benchmark
    read_start = System.monotonic_time(:microsecond)
    Enum.each(test_data, fn {key, _} ->
      MerklePatriciaTree.DB.ETS.get(ets_ref, key)
    end)
    read_time = System.monotonic_time(:microsecond) - read_start
    read_ops_per_sec = 10_000 * 1_000_000 / read_time
    
    IO.puts("  Read:  #{format_number(read_ops_per_sec)} ops/sec (#{read_time} μs total)")
    
    # Mixed operations benchmark
    mixed_start = System.monotonic_time(:microsecond)
    Enum.each(1..5_000, fn i ->
      key = "key_#{i}"
      MerklePatriciaTree.DB.ETS.put!(ets_ref, key, "updated_#{i}")
      MerklePatriciaTree.DB.ETS.get(ets_ref, key)
    end)
    mixed_time = System.monotonic_time(:microsecond) - mixed_start
    mixed_ops_per_sec = 10_000 * 1_000_000 / mixed_time
    
    IO.puts("  Mixed: #{format_number(mixed_ops_per_sec)} ops/sec (#{mixed_time} μs total)")
    
    %{
      write: write_ops_per_sec,
      read: read_ops_per_sec,
      mixed: mixed_ops_per_sec
    }
  end

  def benchmark_batch_operations do
    IO.puts("\n📊 Batch Operations")
    IO.puts("-" |> String.duplicate(40))
    
    {_, ets_ref} = MerklePatriciaTree.DB.ETS.init(:benchmark_ets_batch)
    
    batch_sizes = [100, 1_000, 10_000]
    
    results = Enum.map(batch_sizes, fn size ->
      test_data = for i <- 1..size, do: {"batch_key_#{i}", "batch_value_#{i}"}
      
      # Batch write
      start_time = System.monotonic_time(:microsecond)
      MerklePatriciaTree.DB.ETS.batch_put!(ets_ref, test_data, 100)
      batch_time = System.monotonic_time(:microsecond) - start_time
      ops_per_sec = size * 1_000_000 / batch_time
      
      IO.puts("  Batch size #{String.pad_leading(to_string(size), 6)}: #{format_number(ops_per_sec)} ops/sec")
      
      {size, ops_per_sec}
    end)
    
    Map.new(results)
  end

  def benchmark_concurrent_operations do
    IO.puts("\n📊 Concurrent Operations (100 processes, 1000 ops each)")
    IO.puts("-" |> String.duplicate(40))
    
    {_, ets_ref} = MerklePatriciaTree.DB.ETS.init(:benchmark_ets_concurrent)
    
    process_count = 100
    ops_per_process = 1000
    
    start_time = System.monotonic_time(:microsecond)
    
    tasks = for p <- 1..process_count do
      Task.async(fn ->
        for i <- 1..ops_per_process do
          key = "proc_#{p}_key_#{i}"
          value = "proc_#{p}_value_#{i}"
          MerklePatriciaTree.DB.ETS.put!(ets_ref, key, value)
          MerklePatriciaTree.DB.ETS.get(ets_ref, key)
        end
      end)
    end
    
    # Wait for all tasks to complete
    Enum.each(tasks, &Task.await/1)
    
    total_time = System.monotonic_time(:microsecond) - start_time
    total_ops = process_count * ops_per_process * 2  # Both put and get
    ops_per_sec = total_ops * 1_000_000 / total_time
    
    IO.puts("  Total throughput: #{format_number(ops_per_sec)} ops/sec")
    IO.puts("  Latency per op:   #{Float.round(total_time / total_ops, 2)} μs")
    
    %{
      throughput: ops_per_sec,
      latency: total_time / total_ops
    }
  end

  defp display_summary(single_ops, batch_ops, concurrent) do
    IO.puts("\n" <> "=" |> String.duplicate(60))
    IO.puts("📈 PERFORMANCE SUMMARY")
    IO.puts("=" |> String.duplicate(60))
    
    IO.puts("\n✅ Single Operations:")
    IO.puts("   Write: #{format_number(single_ops.write)} ops/sec")
    IO.puts("   Read:  #{format_number(single_ops.read)} ops/sec")
    IO.puts("   Mixed: #{format_number(single_ops.mixed)} ops/sec")
    
    IO.puts("\n✅ Batch Operations:")
    Enum.each(batch_ops, fn {size, ops} ->
      IO.puts("   Size #{String.pad_leading(to_string(size), 6)}: #{format_number(ops)} ops/sec")
    end)
    
    IO.puts("\n✅ Concurrent Operations:")
    IO.puts("   Throughput: #{format_number(concurrent.throughput)} ops/sec")
    IO.puts("   Latency:    #{Float.round(concurrent.latency, 2)} μs per op")
    
    # Check against target
    target = 300_000
    avg_throughput = (single_ops.write + single_ops.read + single_ops.mixed) / 3
    
    IO.puts("\n" <> "=" |> String.duplicate(60))
    if avg_throughput >= target do
      IO.puts("🎯 TARGET ACHIEVED: Average #{format_number(avg_throughput)} ops/sec")
      IO.puts("   (Target: #{format_number(target)} ops/sec)")
    else
      IO.puts("📊 Current Performance: #{format_number(avg_throughput)} ops/sec")
      IO.puts("   Target: #{format_number(target)} ops/sec")
      IO.puts("   Gap: #{format_number(target - avg_throughput)} ops/sec")
    end
    IO.puts("=" |> String.duplicate(60))
  end

  defp format_number(num) when is_float(num) do
    format_number(round(num))
  end
  
  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end
end

# Run the benchmark
ETSBenchmark.run_all_tests()