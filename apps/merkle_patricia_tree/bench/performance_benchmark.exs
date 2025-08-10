#!/usr/bin/env elixir

# Performance Benchmark: AntidoteDB vs RocksDB
# This script benchmarks the performance characteristics of both database backends
# for the Merkle Patricia Tree implementation.

Mix.install([
  {:benchee, "~> 1.2"},
  {:statistex, "~> 1.0"}
])

# Add the current project to the path
Code.require_file("../../mix.exs")
Code.require_file("../lib/merkle_patricia_tree/db/antidote.ex")
Code.require_file("../lib/merkle_patricia_tree/db/rocksdb.ex")
Code.require_file("../lib/merkle_patricia_tree/trie.ex")

alias MerklePatriciaTree.DB.{Antidote, RocksDB}
alias MerklePatriciaTree.Trie

defmodule PerformanceBenchmark do
  @moduledoc """
  Comprehensive performance benchmarking for AntidoteDB vs RocksDB.

  This module provides benchmarks for:
  - Single key-value operations (get, put, delete)
  - Batch operations
  - Trie operations
  - Memory usage
  - Concurrent operations
  """

  def run_all_benchmarks do
    IO.puts("🚀 Starting Performance Benchmark: AntidoteDB vs RocksDB")
    IO.puts("=" |> String.duplicate(60))

    # Run individual benchmark suites
    benchmark_single_operations()
    benchmark_batch_operations()
    benchmark_trie_operations()
    benchmark_concurrent_operations()
    benchmark_memory_usage()

    IO.puts("\n✅ All benchmarks completed!")
  end

  def benchmark_single_operations do
    IO.puts("\n📊 Benchmarking Single Operations")
    IO.puts("-" |> String.duplicate(40))

    # Prepare test data
    test_data = generate_test_data(1000)

    Benchee.run(
      %{
        "AntidoteDB - Single Put" => fn ->
          {_, connection} = Antidote.init(:benchmark_antidote_single)
          Enum.each(test_data, fn {key, value} ->
            Antidote.put!(connection, key, value)
          end)
          Antidote.close(connection)
        end,
        "RocksDB - Single Put" => fn ->
          db_name = String.to_charlist("/tmp/benchmark_rocksdb_single_#{:rand.uniform(1000)}")
          {_, db_ref} = RocksDB.init(db_name)
          Enum.each(test_data, fn {key, value} ->
            RocksDB.put!(db_ref, key, value)
          end)
          # Note: RocksDB doesn't have a close function in our implementation
        end
      },
      time: 10,
      memory_time: 2,
      warmup: 2,
      formatters: [
        {Benchee.Formatters.Console, extended_statistics: true}
      ]
    )
  end

  def benchmark_batch_operations do
    IO.puts("\n📊 Benchmarking Batch Operations")
    IO.puts("-" |> String.duplicate(40))

    # Prepare test data for batch operations
    batch_sizes = [10, 100, 1000]

    Enum.each(batch_sizes, fn batch_size ->
      IO.puts("\nBatch Size: #{batch_size}")
      test_data = generate_test_data(batch_size)

      Benchee.run(
        %{
          "AntidoteDB - Batch Put" => fn ->
            {_, connection} = Antidote.init(:benchmark_antidote_batch)
            Antidote.batch_put!(connection, test_data, 50)
            Antidote.close(connection)
          end,
          "RocksDB - Batch Put" => fn ->
            db_name = String.to_charlist("/tmp/benchmark_rocksdb_batch_#{:rand.uniform(1000)}")
            {_, db_ref} = RocksDB.init(db_name)
            RocksDB.batch_put!(db_ref, test_data, 50)
          end
        },
        time: 5,
        memory_time: 2,
        warmup: 1,
        formatters: [
          {Benchee.Formatters.Console, extended_statistics: true}
        ]
      )
    end)
  end

  def benchmark_trie_operations do
    IO.puts("\n📊 Benchmarking Trie Operations")
    IO.puts("-" |> String.duplicate(40))

    # Prepare test data for trie operations
    trie_data = generate_trie_data(500)

    Benchee.run(
      %{
        "AntidoteDB - Trie Operations" => fn ->
          {_, connection} = Antidote.init(:benchmark_antidote_trie)
          db = {Antidote, connection}
          trie = Trie.new(db)

          # Insert data into trie
          trie = Enum.reduce(trie_data, trie, fn {key, value}, acc ->
            Trie.put_raw_key!(acc, key, value)
          end)

          # Read data from trie
          Enum.each(trie_data, fn {key, _value} ->
            Trie.get_raw_key(trie, key)
          end)

          Antidote.close(connection)
        end,
        "RocksDB - Trie Operations" => fn ->
          db_name = String.to_charlist("/tmp/benchmark_rocksdb_trie_#{:rand.uniform(1000)}")
          {_, db_ref} = RocksDB.init(db_name)
          db = {RocksDB, db_ref}
          trie = Trie.new(db)

          # Insert data into trie
          trie = Enum.reduce(trie_data, trie, fn {key, value}, acc ->
            Trie.put_raw_key!(acc, key, value)
          end)

          # Read data from trie
          Enum.each(trie_data, fn {key, _value} ->
            Trie.get_raw_key(trie, key)
          end)
        end
      },
      time: 10,
      memory_time: 2,
      warmup: 2,
      formatters: [
        {Benchee.Formatters.Console, extended_statistics: true}
      ]
    )
  end

  def benchmark_concurrent_operations do
    IO.puts("\n📊 Benchmarking Concurrent Operations")
    IO.puts("-" |> String.duplicate(40))

    concurrent_tasks = [5, 10, 20]

    Enum.each(concurrent_tasks, fn num_tasks ->
      IO.puts("\nConcurrent Tasks: #{num_tasks}")

      Benchee.run(
        %{
          "AntidoteDB - Concurrent Operations" => fn ->
            {_, connection} = Antidote.init(:benchmark_antidote_concurrent)

            tasks = for i <- 1..num_tasks do
              Task.async(fn ->
                for j <- 1..100 do
                  key = "concurrent_key_#{i}_#{j}"
                  value = "concurrent_value_#{i}_#{j}"
                  Antidote.put!(connection, key, value)
                  Antidote.get(connection, key)
                end
              end)
            end

            Enum.each(tasks, &Task.await/1)
            Antidote.close(connection)
          end,
          "RocksDB - Concurrent Operations" => fn ->
            db_name = String.to_charlist("/tmp/benchmark_rocksdb_concurrent_#{:rand.uniform(1000)}")
            {_, db_ref} = RocksDB.init(db_name)

            tasks = for i <- 1..num_tasks do
              Task.async(fn ->
                for j <- 1..100 do
                  key = "concurrent_key_#{i}_#{j}"
                  value = "concurrent_value_#{i}_#{j}"
                  RocksDB.put!(db_ref, key, value)
                  RocksDB.get(db_ref, key)
                end
              end)
            end

            Enum.each(tasks, &Task.await/1)
          end
        },
        time: 5,
        memory_time: 2,
        warmup: 1,
        formatters: [
          {Benchee.Formatters.Console, extended_statistics: true}
        ]
      )
    end)
  end

  def benchmark_memory_usage do
    IO.puts("\n📊 Benchmarking Memory Usage")
    IO.puts("-" |> String.duplicate(40))

    # Test memory usage with large datasets
    large_dataset = generate_test_data(10000)

    Benchee.run(
      %{
        "AntidoteDB - Memory Usage" => fn ->
          {_, connection} = Antidote.init(:benchmark_antidote_memory)
          Antidote.batch_put!(connection, large_dataset, 100)

          # Force garbage collection to measure actual memory usage
          :erlang.garbage_collect()

          Antidote.close(connection)
        end,
        "RocksDB - Memory Usage" => fn ->
          db_name = String.to_charlist("/tmp/benchmark_rocksdb_memory_#{:rand.uniform(1000)}")
          {_, db_ref} = RocksDB.init(db_name)
          RocksDB.batch_put!(db_ref, large_dataset, 100)

          # Force garbage collection to measure actual memory usage
          :erlang.garbage_collect()
        end
      },
      time: 1,
      memory_time: 5,
      warmup: 0,
      formatters: [
        {Benchee.Formatters.Console, extended_statistics: true}
      ]
    )
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
PerformanceBenchmark.run_all_benchmarks()
