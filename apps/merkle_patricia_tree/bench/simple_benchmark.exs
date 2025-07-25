#!/usr/bin/env elixir

# Simple Performance Benchmark: AntidoteDB vs RocksDB
# This script provides basic performance measurements without external dependencies

defmodule SimpleBenchmark do
  @moduledoc """
  Simple performance benchmarking for AntidoteDB vs RocksDB.
  Provides basic timing and memory measurements.
  """

  def run_benchmarks do
    IO.puts("🚀 Starting Simple Performance Benchmark: AntidoteDB vs RocksDB")
    IO.puts("=" |> String.duplicate(60))

    # Run individual benchmark suites
    benchmark_single_operations()
    benchmark_batch_operations()
    benchmark_trie_operations()
    benchmark_memory_usage()

    IO.puts("\n✅ All benchmarks completed!")
  end

  def benchmark_single_operations do
    IO.puts("\n📊 Benchmarking Single Operations")
    IO.puts("-" |> String.duplicate(40))

    # Prepare test data
    test_data = generate_test_data(1000)

    # Benchmark AntidoteDB
    antidote_start = System.monotonic_time(:microsecond)
    {_, antidote_conn} = MerklePatriciaTree.DB.Antidote.init(:benchmark_antidote_single)

    Enum.each(test_data, fn {key, value} ->
      MerklePatriciaTree.DB.Antidote.put!(antidote_conn, key, value)
    end)

    antidote_end = System.monotonic_time(:microsecond)
    antidote_time = antidote_end - antidote_start
    MerklePatriciaTree.DB.Antidote.close(antidote_conn)

    # Benchmark RocksDB
    rocksdb_start = System.monotonic_time(:microsecond)
    db_name = String.to_charlist("/tmp/benchmark_rocksdb_single_#{:rand.uniform(1000)}")
    {_, rocksdb_ref} = MerklePatriciaTree.DB.RocksDB.init(db_name)

    Enum.each(test_data, fn {key, value} ->
      MerklePatriciaTree.DB.RocksDB.put!(rocksdb_ref, key, value)
    end)

    rocksdb_end = System.monotonic_time(:microsecond)
    rocksdb_time = rocksdb_end - rocksdb_start

    # Report results
    IO.puts("AntidoteDB - Single Put (1000 operations): #{antidote_time} μs")
    IO.puts("RocksDB - Single Put (1000 operations): #{rocksdb_time} μs")
    IO.puts("Speedup: #{Float.round(rocksdb_time / antidote_time, 2)}x")
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
      {_, antidote_conn} = MerklePatriciaTree.DB.Antidote.init(:benchmark_antidote_batch)
      MerklePatriciaTree.DB.Antidote.batch_put!(antidote_conn, test_data, 50)
      antidote_end = System.monotonic_time(:microsecond)
      antidote_time = antidote_end - antidote_start
      MerklePatriciaTree.DB.Antidote.close(antidote_conn)

      # Benchmark RocksDB
      rocksdb_start = System.monotonic_time(:microsecond)
      db_name = String.to_charlist("/tmp/benchmark_rocksdb_batch_#{:rand.uniform(1000)}")
      {_, rocksdb_ref} = MerklePatriciaTree.DB.RocksDB.init(db_name)
      MerklePatriciaTree.DB.RocksDB.batch_put!(rocksdb_ref, test_data, 50)
      rocksdb_end = System.monotonic_time(:microsecond)
      rocksdb_time = rocksdb_end - rocksdb_start

      # Report results
      IO.puts("  AntidoteDB: #{antidote_time} μs")
      IO.puts("  RocksDB: #{rocksdb_time} μs")
      IO.puts("  Speedup: #{Float.round(rocksdb_time / antidote_time, 2)}x")
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
    trie = Enum.reduce(trie_data, trie, fn {key, value}, acc ->
      MerklePatriciaTree.Trie.put_raw_key!(acc, key, value)
    end)

    # Read data from trie
    Enum.each(trie_data, fn {key, _value} ->
      MerklePatriciaTree.Trie.get_raw_key(trie, key)
    end)

    antidote_end = System.monotonic_time(:microsecond)
    antidote_time = antidote_end - antidote_start
    MerklePatriciaTree.DB.Antidote.close(antidote_conn)

    # Benchmark RocksDB
    rocksdb_start = System.monotonic_time(:microsecond)
    db_name = String.to_charlist("/tmp/benchmark_rocksdb_trie_#{:rand.uniform(1000)}")
    {_, rocksdb_ref} = MerklePatriciaTree.DB.RocksDB.init(db_name)
    db = {MerklePatriciaTree.DB.RocksDB, rocksdb_ref}
    trie = MerklePatriciaTree.Trie.new(db)

    # Insert data into trie
    trie = Enum.reduce(trie_data, trie, fn {key, value}, acc ->
      MerklePatriciaTree.Trie.put_raw_key!(acc, key, value)
    end)

    # Read data from trie
    Enum.each(trie_data, fn {key, _value} ->
      MerklePatriciaTree.Trie.get_raw_key(trie, key)
    end)

    rocksdb_end = System.monotonic_time(:microsecond)
    rocksdb_time = rocksdb_end - rocksdb_start

    # Report results
    IO.puts("AntidoteDB - Trie Operations (500 items): #{antidote_time} μs")
    IO.puts("RocksDB - Trie Operations (500 items): #{rocksdb_time} μs")
    IO.puts("Speedup: #{Float.round(rocksdb_time / antidote_time, 2)}x")
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

    # Measure memory before and after for RocksDB
    :erlang.garbage_collect()
    rocksdb_memory_before = :erlang.memory(:total)

    db_name = String.to_charlist("/tmp/benchmark_rocksdb_memory_#{:rand.uniform(1000)}")
    {_, rocksdb_ref} = MerklePatriciaTree.DB.RocksDB.init(db_name)
    MerklePatriciaTree.DB.RocksDB.batch_put!(rocksdb_ref, large_dataset, 100)
    :erlang.garbage_collect()
    rocksdb_memory_after = :erlang.memory(:total)
    rocksdb_memory_used = rocksdb_memory_after - rocksdb_memory_before

    # Report results
    IO.puts("AntidoteDB - Memory Usage (10,000 items): #{antidote_memory_used} bytes")
    IO.puts("RocksDB - Memory Usage (10,000 items): #{rocksdb_memory_used} bytes")
    IO.puts("Memory Ratio: #{Float.round(antidote_memory_used / rocksdb_memory_used, 2)}x")
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
    for i <- 1..count do
      # Generate Ethereum-like addresses and values
      address = :crypto.strong_rand_bytes(20)
      balance = :crypto.strong_rand_bytes(32)
      {address, balance}
    end
  end
end

# Run the benchmarks
SimpleBenchmark.run_benchmarks()
