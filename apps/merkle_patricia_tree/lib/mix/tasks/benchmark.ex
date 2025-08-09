defmodule Mix.Tasks.Benchmark do
  @moduledoc """
  Benchmark AntidoteDB performance and provide theoretical comparisons.

  ## Usage

      mix benchmark

  This will run comprehensive performance tests for AntidoteDB (ETS fallback)
  and provide theoretical comparisons with RocksDB based on known characteristics.
  """

  use Mix.Task

  @shortdoc "Benchmark AntidoteDB performance"

  @impl Mix.Task
  def run(_args) do
    IO.puts("🚀 Starting Performance Benchmark: AntidoteDB (ETS Fallback)")
    IO.puts("=" |> String.duplicate(60))

    # Run individual benchmark suites
    benchmark_single_operations()
    benchmark_batch_operations()
    benchmark_trie_operations()
    benchmark_memory_usage()
    benchmark_concurrent_operations()

    # Provide theoretical comparisons
    theoretical_comparisons()

    IO.puts("\n✅ All benchmarks completed!")
  end

  def benchmark_single_operations do
    IO.puts("\n📊 Benchmarking Single Operations")
    IO.puts("-" |> String.duplicate(40))

    # Prepare test data
    test_data = generate_test_data(1000)

    # Benchmark AntidoteDB (ETS fallback)
    antidote_start = System.monotonic_time(:microsecond)
    {_, antidote_conn} = MerklePatriciaTree.DB.Antidote.init(:benchmark_antidote_single)

    Enum.each(test_data, fn {key, value} ->
      MerklePatriciaTree.DB.Antidote.put!(antidote_conn, key, value)
    end)

    antidote_end = System.monotonic_time(:microsecond)
    antidote_time = antidote_end - antidote_start
    MerklePatriciaTree.DB.Antidote.close(antidote_conn)

    # Report results
    IO.puts("AntidoteDB (ETS) - Single Put (1000 operations): #{antidote_time} μs")
    IO.puts("Average per operation: #{Float.round(antidote_time / 1000, 2)} μs")
    IO.puts("Operations per second: #{Float.round(1_000_000 / (antidote_time / 1000), 0)}")
  end

  def benchmark_batch_operations do
    IO.puts("\n📊 Benchmarking Batch Operations")
    IO.puts("-" |> String.duplicate(40))

    batch_sizes = [10, 100, 1000]

    Enum.each(batch_sizes, fn batch_size ->
      IO.puts("\nBatch Size: #{batch_size}")
      test_data = generate_test_data(batch_size)

      # Benchmark AntidoteDB
      antidote_start = System.monotonic_time(:microsecond)

      {_, antidote_conn} =
        MerklePatriciaTree.DB.Antidote.init(:"benchmark_antidote_batch_#{batch_size}")

      MerklePatriciaTree.DB.Antidote.batch_put!(antidote_conn, test_data, 50)
      antidote_end = System.monotonic_time(:microsecond)
      antidote_time = antidote_end - antidote_start
      MerklePatriciaTree.DB.Antidote.close(antidote_conn)

      # Report results
      IO.puts("  AntidoteDB (ETS): #{antidote_time} μs")
      IO.puts("  Average per operation: #{Float.round(antidote_time / batch_size, 2)} μs")

      IO.puts(
        "  Operations per second: #{Float.round(1_000_000 / (antidote_time / batch_size), 0)}"
      )
    end)
  end

  def benchmark_trie_operations do
    IO.puts("\n📊 Benchmarking Trie Operations")
    IO.puts("-" |> String.duplicate(40))

    trie_data = generate_trie_data(500)

    # Benchmark AntidoteDB
    antidote_start = System.monotonic_time(:microsecond)
    {_, antidote_conn} = MerklePatriciaTree.DB.Antidote.init(:benchmark_antidote_trie)
    db = {MerklePatriciaTree.DB.Antidote, antidote_conn}
    trie = MerklePatriciaTree.Trie.new(db)

    # Insert data into trie
    trie =
      Enum.reduce(trie_data, trie, fn {key, value}, acc ->
        MerklePatriciaTree.Trie.put_raw_key!(acc, key, value)
      end)

    # Read data from trie
    Enum.each(trie_data, fn {key, _value} ->
      MerklePatriciaTree.Trie.get_raw_key(trie, key)
    end)

    antidote_end = System.monotonic_time(:microsecond)
    antidote_time = antidote_end - antidote_start
    MerklePatriciaTree.DB.Antidote.close(antidote_conn)

    # Report results
    IO.puts("AntidoteDB (ETS) - Trie Operations (500 items): #{antidote_time} μs")
    # 500 writes + 500 reads
    IO.puts("Average per operation: #{Float.round(antidote_time / 1000, 2)} μs")
    IO.puts("Operations per second: #{Float.round(1_000_000 / (antidote_time / 1000), 0)}")
  end

  def benchmark_memory_usage do
    IO.puts("\n📊 Benchmarking Memory Usage")
    IO.puts("-" |> String.duplicate(40))

    large_dataset = generate_test_data(10000)

    # Measure memory before and after for AntidoteDB
    :erlang.garbage_collect()
    antidote_memory_before = :erlang.memory(:total)

    {_, antidote_conn} = MerklePatriciaTree.DB.Antidote.init(:benchmark_antidote_memory)
    MerklePatriciaTree.DB.Antidote.batch_put!(antidote_conn, large_dataset, 100)
    :erlang.garbage_collect()
    antidote_memory_after = :erlang.memory(:total)
    antidote_memory_used = antidote_memory_after - antidote_memory_before
    MerklePatriciaTree.DB.Antidote.close(antidote_conn)

    # Report results
    IO.puts("AntidoteDB (ETS) - Memory Usage (10,000 items): #{antidote_memory_used} bytes")
    IO.puts("Memory per item: #{Float.round(antidote_memory_used / 10000, 2)} bytes")
    IO.puts("Memory in MB: #{Float.round(antidote_memory_used / 1024 / 1024, 2)} MB")
  end

  def benchmark_concurrent_operations do
    IO.puts("\n📊 Benchmarking Concurrent Operations")
    IO.puts("-" |> String.duplicate(40))

    concurrent_tasks = [5, 10, 20]

    Enum.each(concurrent_tasks, fn num_tasks ->
      IO.puts("\nConcurrent Tasks: #{num_tasks}")

      # Benchmark AntidoteDB
      antidote_start = System.monotonic_time(:microsecond)

      {_, antidote_conn} =
        MerklePatriciaTree.DB.Antidote.init(:"benchmark_antidote_concurrent_#{num_tasks}")

      tasks =
        for i <- 1..num_tasks do
          Task.async(fn ->
            for j <- 1..100 do
              key = "concurrent_key_#{i}_#{j}"
              value = "concurrent_value_#{i}_#{j}"
              MerklePatriciaTree.DB.Antidote.put!(antidote_conn, key, value)
              MerklePatriciaTree.DB.Antidote.get(antidote_conn, key)
            end
          end)
        end

      Enum.each(tasks, &Task.await/1)
      antidote_end = System.monotonic_time(:microsecond)
      antidote_time = antidote_end - antidote_start
      MerklePatriciaTree.DB.Antidote.close(antidote_conn)

      # 100 puts + 100 gets per task
      total_operations = num_tasks * 100 * 2

      # Report results
      IO.puts("  AntidoteDB (ETS): #{antidote_time} μs")
      IO.puts("  Total operations: #{total_operations}")
      IO.puts("  Average per operation: #{Float.round(antidote_time / total_operations, 2)} μs")

      IO.puts(
        "  Operations per second: #{Float.round(1_000_000 / (antidote_time / total_operations), 0)}"
      )
    end)
  end

  def theoretical_comparisons do
    IO.puts("\n📊 Theoretical Performance Comparisons")
    IO.puts("-" |> String.duplicate(40))

    IO.puts("""
    Based on known characteristics of ETS vs RocksDB:

    🚀 ETS (Current AntidoteDB Fallback):
    - In-memory storage (very fast)
    - No disk I/O overhead
    - Excellent for development and testing
    - Memory usage: ~100-200 bytes per key-value pair
    - Latency: ~1-5 μs per operation

    💾 RocksDB (Production Database):
    - Persistent storage with compression
    - Optimized for SSD storage
    - Excellent for production workloads
    - Memory usage: ~50-100 bytes per key-value pair (compressed)
    - Latency: ~10-100 μs per operation (depends on cache hit rate)

    🔄 AntidoteDB (Future Implementation):
    - Distributed transactional database
    - CRDT support for concurrent updates
    - Network latency overhead
    - Excellent for distributed blockchain applications
    - Latency: ~1-10ms per operation (network dependent)

    📈 Expected Performance Improvements:
    - RocksDB: 2-5x slower than ETS, but persistent
    - AntidoteDB: 100-1000x slower than ETS, but distributed
    - Memory efficiency: RocksDB > AntidoteDB > ETS
    - Scalability: AntidoteDB > RocksDB > ETS
    """)
  end

  # Helper functions
  defp generate_test_data(count) do
    for i <- 1..count do
      key = "benchmark_key_#{i}"
      value = "benchmark_value_#{i}_#{:crypto.strong_rand_bytes(64)}"
      {key, value}
    end
  end

  defp generate_trie_data(count) do
    for _i <- 1..count do
      # Generate Ethereum-like addresses and values
      address = :crypto.strong_rand_bytes(20)
      balance = :crypto.strong_rand_bytes(32)
      {address, balance}
    end
  end
end
