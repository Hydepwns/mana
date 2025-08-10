defmodule Mix.Tasks.Benchmark.Verkle do
  @moduledoc """
  Performance benchmarking for Verkle Trees vs Merkle Patricia Trees.
  
  Usage:
    mix benchmark.verkle [options]
    
  Options:
    --operations N    Number of operations to perform (default: 10000)
    --keys N         Number of unique keys (default: 1000)
    --witness-size N Number of keys per witness (default: 10)
    --parallel       Run parallel benchmarks
    --detailed       Show detailed metrics
  """
  
  use Mix.Task
  require Logger
  
  alias VerkleTree
  alias VerkleTree.{Witness, Migration}
  alias MerklePatriciaTree.{Trie, Test}

  @shortdoc "Benchmark verkle tree performance"
  
  def run(args) do
    Application.ensure_all_started(:merkle_patricia_tree)
    
    {opts, _, _} = OptionParser.parse(args,
      switches: [
        operations: :integer,
        keys: :integer,
        witness_size: :integer,
        parallel: :boolean,
        detailed: :boolean
      ]
    )
    
    config = %{
      operations: Keyword.get(opts, :operations, 10_000),
      keys: Keyword.get(opts, :keys, 1_000),
      witness_size: Keyword.get(opts, :witness_size, 10),
      parallel: Keyword.get(opts, :parallel, false),
      detailed: Keyword.get(opts, :detailed, false)
    }
    
    Logger.info("Starting Verkle Tree Performance Benchmarks")
    Logger.info("Configuration: #{inspect(config)}")
    
    results = %{
      verkle: run_verkle_benchmarks(config),
      mpt: run_mpt_benchmarks(config),
      comparison: %{}
    }
    
    results = Map.put(results, :comparison, calculate_comparisons(results))
    
    print_results(results, config)
    
    if config.parallel do
      parallel_results = run_parallel_benchmarks(config)
      print_parallel_results(parallel_results)
    end
  end
  
  # Verkle Tree Benchmarks
  
  defp run_verkle_benchmarks(config) do
    Logger.info("\n=== Verkle Tree Benchmarks ===")
    
    db = Test.random_ets_db()
    tree = VerkleTree.new(db)
    
    # Generate test data
    test_data = generate_test_data(config.keys)
    
    results = %{
      insert: benchmark_verkle_insert(tree, test_data, config),
      read: benchmark_verkle_read(tree, test_data, config),
      update: benchmark_verkle_update(tree, test_data, config),
      delete: benchmark_verkle_delete(tree, test_data, config),
      witness: benchmark_verkle_witness(tree, test_data, config),
      migration: benchmark_verkle_migration(tree, config)
    }
    
    Logger.info("Verkle benchmarks complete")
    results
  end
  
  defp benchmark_verkle_insert(tree, test_data, config) do
    Logger.info("  Benchmarking insert operations...")
    
    {time, updated_tree} = :timer.tc(fn ->
      Enum.reduce(Enum.take(test_data, config.operations), tree, fn {key, value}, acc ->
        VerkleTree.put(acc, key, value)
      end)
    end)
    
    ops_per_sec = config.operations * 1_000_000 / time
    
    %{
      total_time_us: time,
      operations: config.operations,
      ops_per_second: Float.round(ops_per_sec, 2),
      avg_time_us: Float.round(time / config.operations, 2),
      final_root: Base.encode16(updated_tree.root_commitment, case: :lower)
    }
  end
  
  defp benchmark_verkle_read(tree, test_data, config) do
    Logger.info("  Benchmarking read operations...")
    
    # First populate the tree
    tree = Enum.reduce(test_data, tree, fn {key, value}, acc ->
      VerkleTree.put(acc, key, value)
    end)
    
    keys_to_read = test_data |> Enum.take(config.operations) |> Enum.map(fn {k, _} -> k end)
    
    {time, _results} = :timer.tc(fn ->
      Enum.map(keys_to_read, fn key ->
        VerkleTree.get(tree, key)
      end)
    end)
    
    ops_per_sec = config.operations * 1_000_000 / time
    
    %{
      total_time_us: time,
      operations: config.operations,
      ops_per_second: Float.round(ops_per_sec, 2),
      avg_time_us: Float.round(time / config.operations, 2)
    }
  end
  
  defp benchmark_verkle_update(tree, test_data, config) do
    Logger.info("  Benchmarking update operations...")
    
    # First populate the tree
    tree = Enum.reduce(test_data, tree, fn {key, value}, acc ->
      VerkleTree.put(acc, key, value)
    end)
    
    updates = test_data 
              |> Enum.take(config.operations) 
              |> Enum.map(fn {k, _} -> {k, "updated_#{k}"} end)
    
    {time, _updated_tree} = :timer.tc(fn ->
      Enum.reduce(updates, tree, fn {key, value}, acc ->
        VerkleTree.put(acc, key, value)
      end)
    end)
    
    ops_per_sec = config.operations * 1_000_000 / time
    
    %{
      total_time_us: time,
      operations: config.operations,
      ops_per_second: Float.round(ops_per_sec, 2),
      avg_time_us: Float.round(time / config.operations, 2)
    }
  end
  
  defp benchmark_verkle_delete(tree, test_data, config) do
    Logger.info("  Benchmarking delete operations...")
    
    # First populate the tree
    tree = Enum.reduce(test_data, tree, fn {key, value}, acc ->
      VerkleTree.put(acc, key, value)
    end)
    
    keys_to_delete = test_data |> Enum.take(config.operations) |> Enum.map(fn {k, _} -> k end)
    
    {time, _updated_tree} = :timer.tc(fn ->
      Enum.reduce(keys_to_delete, tree, fn key, acc ->
        VerkleTree.remove(acc, key)
      end)
    end)
    
    ops_per_sec = config.operations * 1_000_000 / time
    
    %{
      total_time_us: time,
      operations: config.operations,
      ops_per_second: Float.round(ops_per_sec, 2),
      avg_time_us: Float.round(time / config.operations, 2)
    }
  end
  
  defp benchmark_verkle_witness(tree, test_data, config) do
    Logger.info("  Benchmarking witness generation...")
    
    # First populate the tree
    tree = Enum.reduce(test_data, tree, fn {key, value}, acc ->
      VerkleTree.put(acc, key, value)
    end)
    
    # Generate witnesses for batches of keys
    witness_batches = test_data
                      |> Enum.map(fn {k, _} -> k end)
                      |> Enum.chunk_every(config.witness_size)
                      |> Enum.take(div(config.operations, config.witness_size))
    
    {gen_time, witnesses} = :timer.tc(fn ->
      Enum.map(witness_batches, fn keys ->
        VerkleTree.generate_witness(tree, keys)
      end)
    end)
    
    # Benchmark witness verification
    witness_data = Enum.zip(witnesses, witness_batches)
    kvs_for_verification = test_data 
                           |> Enum.take(config.witness_size)
                           |> Enum.map(fn {k, v} -> {k, v} end)
    
    {verify_time, _results} = :timer.tc(fn ->
      Enum.map(witness_data, fn {witness, _keys} ->
        Witness.verify(witness, tree.root_commitment, kvs_for_verification)
      end)
    end)
    
    witness_count = length(witnesses)
    avg_witness_size = witnesses
                       |> Enum.map(&Witness.size/1)
                       |> Enum.sum()
                       |> Kernel./(witness_count)
    
    %{
      generation_time_us: gen_time,
      verification_time_us: verify_time,
      witness_count: witness_count,
      keys_per_witness: config.witness_size,
      avg_witness_size_bytes: Float.round(avg_witness_size, 2),
      gen_per_second: Float.round(witness_count * 1_000_000 / gen_time, 2),
      verify_per_second: Float.round(witness_count * 1_000_000 / verify_time, 2)
    }
  end
  
  defp benchmark_verkle_migration(tree, config) do
    Logger.info("  Benchmarking state migration...")
    
    # Create an MPT with test data
    mpt_db = Test.random_ets_db()
    mpt = Trie.new(mpt_db)
    
    test_data = generate_test_data(div(config.keys, 10))  # Smaller dataset for migration
    
    mpt = Enum.reduce(test_data, mpt, fn {key, value}, acc ->
      Trie.update_key(acc, key, value)
    end)
    
    # Benchmark migration initialization
    {init_time, migration_state} = :timer.tc(fn ->
      Migration.new(mpt, tree.db)
    end)
    
    # Benchmark access-driven migration
    keys_to_access = test_data |> Enum.map(fn {k, _} -> k end)
    
    {access_time, final_state} = :timer.tc(fn ->
      Enum.reduce(keys_to_access, migration_state, fn key, acc ->
        {_, updated} = Migration.get_with_migration(acc, key)
        updated
      end)
    end)
    
    %{
      init_time_us: init_time,
      access_migration_time_us: access_time,
      keys_migrated: length(keys_to_access),
      migration_progress: Migration.migration_progress(final_state),
      avg_migration_time_us: Float.round(access_time / length(keys_to_access), 2)
    }
  end
  
  # MPT Benchmarks for comparison
  
  defp run_mpt_benchmarks(config) do
    Logger.info("\n=== Merkle Patricia Tree Benchmarks ===")
    
    db = Test.random_ets_db()
    trie = Trie.new(db)
    
    test_data = generate_test_data(config.keys)
    
    results = %{
      insert: benchmark_mpt_insert(trie, test_data, config),
      read: benchmark_mpt_read(trie, test_data, config),
      update: benchmark_mpt_update(trie, test_data, config),
      delete: benchmark_mpt_delete(trie, test_data, config)
    }
    
    Logger.info("MPT benchmarks complete")
    results
  end
  
  defp benchmark_mpt_insert(trie, test_data, config) do
    Logger.info("  Benchmarking MPT insert operations...")
    
    {time, _updated_trie} = :timer.tc(fn ->
      Enum.reduce(Enum.take(test_data, config.operations), trie, fn {key, value}, acc ->
        Trie.update_key(acc, key, value)
      end)
    end)
    
    ops_per_sec = config.operations * 1_000_000 / time
    
    %{
      total_time_us: time,
      operations: config.operations,
      ops_per_second: Float.round(ops_per_sec, 2),
      avg_time_us: Float.round(time / config.operations, 2)
    }
  end
  
  defp benchmark_mpt_read(trie, test_data, config) do
    Logger.info("  Benchmarking MPT read operations...")
    
    # First populate the trie
    trie = Enum.reduce(test_data, trie, fn {key, value}, acc ->
      Trie.update_key(acc, key, value)
    end)
    
    keys_to_read = test_data |> Enum.take(config.operations) |> Enum.map(fn {k, _} -> k end)
    
    {time, _results} = :timer.tc(fn ->
      Enum.map(keys_to_read, fn key ->
        Trie.get_key(trie, key)
      end)
    end)
    
    ops_per_sec = config.operations * 1_000_000 / time
    
    %{
      total_time_us: time,
      operations: config.operations,
      ops_per_second: Float.round(ops_per_sec, 2),
      avg_time_us: Float.round(time / config.operations, 2)
    }
  end
  
  defp benchmark_mpt_update(trie, test_data, config) do
    Logger.info("  Benchmarking MPT update operations...")
    
    # First populate the trie
    trie = Enum.reduce(test_data, trie, fn {key, value}, acc ->
      Trie.update_key(acc, key, value)
    end)
    
    updates = test_data 
              |> Enum.take(config.operations) 
              |> Enum.map(fn {k, _} -> {k, "updated_#{k}"} end)
    
    {time, _updated_trie} = :timer.tc(fn ->
      Enum.reduce(updates, trie, fn {key, value}, acc ->
        Trie.update_key(acc, key, value)
      end)
    end)
    
    ops_per_sec = config.operations * 1_000_000 / time
    
    %{
      total_time_us: time,
      operations: config.operations,
      ops_per_second: Float.round(ops_per_sec, 2),
      avg_time_us: Float.round(time / config.operations, 2)
    }
  end
  
  defp benchmark_mpt_delete(trie, test_data, config) do
    Logger.info("  Benchmarking MPT delete operations...")
    
    # First populate the trie  
    trie = Enum.reduce(test_data, trie, fn {key, value}, acc ->
      Trie.update_key(acc, key, value)
    end)
    
    keys_to_delete = test_data |> Enum.take(config.operations) |> Enum.map(fn {k, _} -> k end)
    
    {time, _updated_trie} = :timer.tc(fn ->
      Enum.reduce(keys_to_delete, trie, fn key, acc ->
        Trie.remove_key(acc, key)
      end)
    end)
    
    ops_per_sec = config.operations * 1_000_000 / time
    
    %{
      total_time_us: time,
      operations: config.operations,
      ops_per_second: Float.round(ops_per_sec, 2),
      avg_time_us: Float.round(time / config.operations, 2)
    }
  end
  
  # Parallel benchmarks
  
  defp run_parallel_benchmarks(config) do
    Logger.info("\n=== Parallel Performance Benchmarks ===")
    
    task_counts = [1, 2, 4, 8, 16]
    
    Enum.map(task_counts, fn task_count ->
      Logger.info("  Testing with #{task_count} parallel tasks...")
      
      verkle_result = benchmark_parallel_verkle(task_count, config)
      mpt_result = benchmark_parallel_mpt(task_count, config)
      
      %{
        task_count: task_count,
        verkle: verkle_result,
        mpt: mpt_result
      }
    end)
  end
  
  defp benchmark_parallel_verkle(task_count, config) do
    ops_per_task = div(config.operations, task_count)
    
    {time, _results} = :timer.tc(fn ->
      tasks = for _ <- 1..task_count do
        Task.async(fn ->
          db = Test.random_ets_db()
          tree = VerkleTree.new(db)
          test_data = generate_test_data(ops_per_task)
          
          Enum.reduce(test_data, tree, fn {key, value}, acc ->
            VerkleTree.put(acc, key, value)
          end)
        end)
      end
      
      Task.await_many(tasks, 30_000)
    end)
    
    total_ops = task_count * ops_per_task
    ops_per_sec = total_ops * 1_000_000 / time
    
    %{
      total_time_us: time,
      total_operations: total_ops,
      ops_per_second: Float.round(ops_per_sec, 2),
      speedup: Float.round(ops_per_sec / (config.operations * 1_000_000 / time), 2)
    }
  end
  
  defp benchmark_parallel_mpt(task_count, config) do
    ops_per_task = div(config.operations, task_count)
    
    {time, _results} = :timer.tc(fn ->
      tasks = for _ <- 1..task_count do
        Task.async(fn ->
          db = Test.random_ets_db()
          trie = Trie.new(db)
          test_data = generate_test_data(ops_per_task)
          
          Enum.reduce(test_data, trie, fn {key, value}, acc ->
            Trie.update_key(acc, key, value)
          end)
        end)
      end
      
      Task.await_many(tasks, 30_000)
    end)
    
    total_ops = task_count * ops_per_task
    ops_per_sec = total_ops * 1_000_000 / time
    
    %{
      total_time_us: time,
      total_operations: total_ops,
      ops_per_second: Float.round(ops_per_sec, 2),
      speedup: Float.round(ops_per_sec / (config.operations * 1_000_000 / time), 2)
    }
  end
  
  # Helper functions
  
  defp generate_test_data(count) do
    for i <- 1..count do
      key = "key_#{i}_#{:rand.uniform(1_000_000)}"
      value = "value_#{i}_data_#{:crypto.strong_rand_bytes(20) |> Base.encode16()}"
      {key, value}
    end
  end
  
  defp calculate_comparisons(results) do
    %{
      insert_speedup: calculate_speedup(results.verkle.insert, results.mpt.insert),
      read_speedup: calculate_speedup(results.verkle.read, results.mpt.read),
      update_speedup: calculate_speedup(results.verkle.update, results.mpt.update),
      delete_speedup: calculate_speedup(results.verkle.delete, results.mpt.delete),
      witness_advantage: results.verkle.witness.avg_witness_size_bytes
    }
  end
  
  defp calculate_speedup(verkle_result, mpt_result) do
    Float.round(verkle_result.ops_per_second / mpt_result.ops_per_second, 2)
  end
  
  defp print_results(results, config) do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("VERKLE TREE PERFORMANCE BENCHMARK RESULTS")
    IO.puts(String.duplicate("=", 80))
    
    IO.puts("\nConfiguration:")
    IO.puts("  Operations: #{config.operations}")
    IO.puts("  Unique Keys: #{config.keys}")
    IO.puts("  Witness Size: #{config.witness_size}")
    
    IO.puts("\n--- Verkle Tree Performance ---")
    print_operation_results("Insert", results.verkle.insert)
    print_operation_results("Read", results.verkle.read)
    print_operation_results("Update", results.verkle.update)
    print_operation_results("Delete", results.verkle.delete)
    
    IO.puts("\n--- Witness Performance ---")
    witness = results.verkle.witness
    IO.puts("  Generation: #{witness.gen_per_second} witnesses/sec")
    IO.puts("  Verification: #{witness.verify_per_second} witnesses/sec")
    IO.puts("  Average Size: #{witness.avg_witness_size_bytes} bytes")
    IO.puts("  Keys per Witness: #{witness.keys_per_witness}")
    
    IO.puts("\n--- State Migration ---")
    migration = results.verkle.migration
    IO.puts("  Init Time: #{format_time(migration.init_time_us)}")
    IO.puts("  Keys Migrated: #{migration.keys_migrated}")
    IO.puts("  Avg Migration: #{migration.avg_migration_time_us} μs/key")
    IO.puts("  Progress: #{migration.migration_progress}%")
    
    IO.puts("\n--- Merkle Patricia Tree Performance ---")
    print_operation_results("Insert", results.mpt.insert)
    print_operation_results("Read", results.mpt.read)
    print_operation_results("Update", results.mpt.update)
    print_operation_results("Delete", results.mpt.delete)
    
    IO.puts("\n--- Performance Comparison ---")
    comp = results.comparison
    IO.puts("  Insert: #{format_speedup(comp.insert_speedup)}")
    IO.puts("  Read: #{format_speedup(comp.read_speedup)}")
    IO.puts("  Update: #{format_speedup(comp.update_speedup)}")
    IO.puts("  Delete: #{format_speedup(comp.delete_speedup)}")
    IO.puts("  Witness Size: #{comp.witness_advantage} bytes (verkle)")
    
    IO.puts("\n" <> String.duplicate("=", 80))
  end
  
  defp print_operation_results(name, result) do
    IO.puts("  #{String.pad_trailing(name, 10)}: #{result.ops_per_second} ops/sec (#{result.avg_time_us} μs/op)")
  end
  
  defp print_parallel_results(results) do
    IO.puts("\n--- Parallel Performance Scaling ---")
    
    Enum.each(results, fn result ->
      IO.puts("\n  #{result.task_count} Parallel Tasks:")
      IO.puts("    Verkle: #{result.verkle.ops_per_second} ops/sec (#{result.verkle.speedup}x speedup)")
      IO.puts("    MPT: #{result.mpt.ops_per_second} ops/sec (#{result.mpt.speedup}x speedup)")
    end)
  end
  
  defp format_time(microseconds) when microseconds < 1000 do
    "#{microseconds} μs"
  end
  
  defp format_time(microseconds) when microseconds < 1_000_000 do
    "#{Float.round(microseconds / 1000, 2)} ms"
  end
  
  defp format_time(microseconds) do
    "#{Float.round(microseconds / 1_000_000, 2)} s"
  end
  
  defp format_speedup(speedup) when speedup >= 1.0 do
    "#{speedup}x faster"
  end
  
  defp format_speedup(speedup) do
    "#{Float.round(1 / speedup, 2)}x slower"
  end
end