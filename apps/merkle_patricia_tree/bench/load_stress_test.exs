defmodule MerklePatriciaTree.Bench.LoadStressTest do
  @moduledoc """
  Comprehensive load testing and stress testing framework for Phase 2.3.

  This benchmark evaluates the AntidoteDB implementation under realistic
  blockchain workloads and stress conditions.

  ## Test Scenarios

  - **Realistic Blockchain Data**: Ethereum state tree operations
  - **High Concurrency**: Multiple concurrent transactions
  - **Large State Trees**: Memory optimization testing
  - **Network Stress**: Simulated network failures and latency
  - **CRDT Operations**: Advanced CRDT performance testing
  - **Memory Pressure**: Memory usage under load

  ## Usage

      # Run all load tests
      Mix.Task.run("bench", ["load_stress_test"])

      # Run specific test scenario
      MerklePatriciaTree.Bench.LoadStressTest.run_blockchain_scenario()
  """

  require Logger

  # Test configuration
  @test_duration 60_000  # 60 seconds
  @concurrent_users 100
  @operations_per_user 1000
  @large_state_size 1_000_000  # 1M items
  @network_latency_range {10, 1000}  # 10ms to 1s

  def run_all_tests do
    IO.puts("🚀 Starting Comprehensive Load & Stress Testing")
    IO.puts("=" |> String.duplicate(60))

    results = %{
      blockchain_scenario: run_blockchain_scenario(),
      high_concurrency: run_high_concurrency_test(),
      large_state_operations: run_large_state_test(),
      network_stress: run_network_stress_test(),
      crdt_performance: run_crdt_performance_test(),
      memory_pressure: run_memory_pressure_test(),
      mixed_workload: run_mixed_workload_test()
    }

    generate_load_test_report(results)
    results
  end

  @doc """
  Realistic blockchain scenario with Ethereum state tree operations.
  """
  def run_blockchain_scenario do
    IO.puts("📊 Running Blockchain Scenario Test")

    # Initialize database
    db = init_test_database("blockchain_scenario")

    # Generate realistic Ethereum state data
    state_data = generate_ethereum_state_data(10_000)

    start_time = System.monotonic_time(:microsecond)

    # Simulate blockchain operations
    results = %{
      block_processing: process_blocks(db, state_data),
      state_transitions: process_state_transitions(db, state_data),
      trie_operations: process_trie_operations(db, state_data),
      concurrent_access: test_concurrent_state_access(db, state_data)
    }

    end_time = System.monotonic_time(:microsecond)
    duration = end_time - start_time

    %{
      scenario: "blockchain_realistic",
      duration_ms: duration / 1000,
      operations: count_operations(results),
      throughput_ops_per_sec: count_operations(results) / (duration / 1_000_000),
      results: results
    }
  end

  @doc """
  High concurrency test with multiple simultaneous users.
  """
  def run_high_concurrency_test do
    IO.puts("👥 Running High Concurrency Test")

    db = init_test_database("high_concurrency")

    start_time = System.monotonic_time(:microsecond)

    # Simulate multiple concurrent users
    tasks = Enum.map(1..@concurrent_users, fn user_id ->
      Task.async(fn ->
        simulate_user_workload(db, user_id, @operations_per_user)
      end)
    end)

    results = Task.await_many(tasks, @test_duration)

    end_time = System.monotonic_time(:microsecond)
    duration = end_time - start_time

    %{
      scenario: "high_concurrency",
      duration_ms: duration / 1000,
      concurrent_users: @concurrent_users,
      operations_per_user: @operations_per_user,
      total_operations: @concurrent_users * @operations_per_user,
      throughput_ops_per_sec: (@concurrent_users * @operations_per_user) / (duration / 1_000_000),
      results: results
    }
  end

  @doc """
  Large state tree operations with memory optimization testing.
  """
  def run_large_state_test do
    IO.puts("🌳 Running Large State Tree Test")

    db = init_test_database("large_state")

    # Generate large state tree
    large_state = generate_large_state_tree(@large_state_size)

    start_time = System.monotonic_time(:microsecond)

    results = %{
      state_loading: load_large_state(db, large_state),
      state_traversal: traverse_large_state(db, large_state),
      memory_usage: measure_memory_usage(db),
      garbage_collection: test_garbage_collection(db)
    }

    end_time = System.monotonic_time(:microsecond)
    duration = end_time - start_time

    %{
      scenario: "large_state_tree",
      duration_ms: duration / 1000,
      state_size: @large_state_size,
      memory_usage_mb: results.memory_usage.total_mb,
      throughput_ops_per_sec: @large_state_size / (duration / 1_000_000),
      results: results
    }
  end

  @doc """
  Network stress testing with simulated failures and latency.
  """
  def run_network_stress_test do
    IO.puts("🌐 Running Network Stress Test")

    db = init_test_database("network_stress")

    start_time = System.monotonic_time(:microsecond)

    results = %{
      network_latency: simulate_network_latency(db),
      connection_failures: simulate_connection_failures(db),
      node_failures: simulate_node_failures(db),
      recovery_time: measure_recovery_time(db)
    }

    end_time = System.monotonic_time(:microsecond)
    duration = end_time - start_time

    %{
      scenario: "network_stress",
      duration_ms: duration / 1000,
      failure_rate: results.connection_failures.failure_rate,
      avg_recovery_time_ms: results.recovery_time.avg_ms,
      results: results
    }
  end

  @doc """
  CRDT performance testing with advanced operations.
  """
  def run_crdt_performance_test do
    IO.puts("🔄 Running CRDT Performance Test")

    db = init_test_database("crdt_performance")

    start_time = System.monotonic_time(:microsecond)

    results = %{
      counter_operations: test_crdt_counters(db),
      set_operations: test_crdt_sets(db),
      map_operations: test_crdt_maps(db),
      conflict_resolution: test_conflict_resolution(db)
    }

    end_time = System.monotonic_time(:microsecond)
    duration = end_time - start_time

    %{
      scenario: "crdt_performance",
      duration_ms: duration / 1000,
      crdt_operations: count_crdt_operations(results),
      conflict_resolution_time_ms: results.conflict_resolution.avg_time_ms,
      results: results
    }
  end

  @doc """
  Memory pressure testing under load.
  """
  def run_memory_pressure_test do
    IO.puts("💾 Running Memory Pressure Test")

    db = init_test_database("memory_pressure")

    start_time = System.monotonic_time(:microsecond)

    results = %{
      memory_allocation: test_memory_allocation(db),
      memory_cleanup: test_memory_cleanup(db),
      memory_fragmentation: test_memory_fragmentation(db),
      gc_performance: test_gc_under_pressure(db)
    }

    end_time = System.monotonic_time(:microsecond)
    duration = end_time - start_time

    %{
      scenario: "memory_pressure",
      duration_ms: duration / 1000,
      peak_memory_mb: results.memory_allocation.peak_mb,
      memory_efficiency: results.memory_cleanup.efficiency_percent,
      results: results
    }
  end

  @doc """
  Mixed workload testing with realistic usage patterns.
  """
  def run_mixed_workload_test do
    IO.puts("🎯 Running Mixed Workload Test")

    db = init_test_database("mixed_workload")

    start_time = System.monotonic_time(:microsecond)

    results = %{
      read_heavy: test_read_heavy_workload(db),
      write_heavy: test_write_heavy_workload(db),
      balanced: test_balanced_workload(db),
      burst_traffic: test_burst_traffic(db)
    }

    end_time = System.monotonic_time(:microsecond)
    duration = end_time - start_time

    %{
      scenario: "mixed_workload",
      duration_ms: duration / 1000,
      total_operations: count_mixed_operations(results),
      avg_latency_ms: calculate_avg_latency(results),
      results: results
    }
  end

  # Private helper functions

  defp init_test_database(name) do
    MerklePatriciaTree.DB.Antidote.init(name)
  end

  defp generate_ethereum_state_data(count) do
    Enum.map(1..count, fn i ->
      %{
        address: generate_ethereum_address(),
        balance: :rand.uniform(1_000_000_000),
        nonce: :rand.uniform(1000),
        code: generate_contract_code(),
        storage: generate_storage_data()
      }
    end)
  end

  defp generate_ethereum_address do
    :crypto.strong_rand_bytes(20)
    |> Base.encode16(case: :lower)
    |> String.pad_leading(40, "0")
  end

  defp generate_contract_code do
    # Generate random contract bytecode
    :crypto.strong_rand_bytes(:rand.uniform(1000))
  end

  defp generate_storage_data do
    Enum.map(1..:rand.uniform(10), fn _ ->
      {generate_storage_key(), generate_storage_value()}
    end)
    |> Map.new()
  end

  defp generate_storage_key do
    :crypto.strong_rand_bytes(32)
  end

  defp generate_storage_value do
    :crypto.strong_rand_bytes(32)
  end

  defp process_blocks(db, state_data) do
    # Simulate block processing
    Enum.map(1..100, fn block_number ->
      block_start = System.monotonic_time(:microsecond)

      # Process transactions in block
      transactions = generate_block_transactions(state_data, 100)
      Enum.each(transactions, fn tx ->
        process_transaction(db, tx)
      end)

      block_end = System.monotonic_time(:microsecond)
      %{
        block_number: block_number,
        transactions: length(transactions),
        processing_time_ms: (block_end - block_start) / 1000
      }
    end)
  end

  defp generate_block_transactions(state_data, count) do
    Enum.map(1..count, fn _ ->
      %{
        from: Enum.random(state_data).address,
        to: Enum.random(state_data).address,
        value: :rand.uniform(1000),
        gas: :rand.uniform(21000),
        gas_price: :rand.uniform(20)
      }
    end)
  end

  defp process_transaction(db, transaction) do
    # Simulate transaction processing
    MerklePatriciaTree.DB.Antidote.put!(db, "tx_#{:rand.uniform(1000000)}", :erlang.term_to_binary(transaction))
  end

  defp process_state_transitions(db, state_data) do
    # Simulate state transitions
    Enum.map(state_data, fn state ->
      transition_start = System.monotonic_time(:microsecond)

      # Update state
      updated_state = %{state | balance: state.balance + :rand.uniform(100) - 50}
      MerklePatriciaTree.DB.Antidote.put!(db, "state_#{state.address}", :erlang.term_to_binary(updated_state))

      transition_end = System.monotonic_time(:microsecond)
      %{
        address: state.address,
        transition_time_ms: (transition_end - transition_start) / 1000
      }
    end)
  end

  defp process_trie_operations(db, state_data) do
    # Simulate trie operations
    Enum.map(state_data, fn state ->
      trie_start = System.monotonic_time(:microsecond)

      # Perform trie operations
      MerklePatriciaTree.DB.Antidote.put!(db, "trie_#{state.address}", :erlang.term_to_binary(state))
      MerklePatriciaTree.DB.Antidote.get(db, "trie_#{state.address}")

      trie_end = System.monotonic_time(:microsecond)
      %{
        address: state.address,
        trie_time_ms: (trie_end - trie_start) / 1000
      }
    end)
  end

  defp test_concurrent_state_access(db, state_data) do
    # Test concurrent access to state
    tasks = Enum.map(1..10, fn _ ->
      Task.async(fn ->
        Enum.map(1..100, fn _ ->
          state = Enum.random(state_data)
          MerklePatriciaTree.DB.Antidote.get(db, "state_#{state.address}")
        end)
      end)
    end)

    Task.await_many(tasks, 30_000)
  end

  defp simulate_user_workload(db, user_id, operation_count) do
    Enum.map(1..operation_count, fn op_id ->
      operation_start = System.monotonic_time(:microsecond)

      # Simulate user operations
      case :rand.uniform(3) do
        1 -> MerklePatriciaTree.DB.Antidote.put!(db, "user_#{user_id}_#{op_id}", "value_#{op_id}")
        2 -> MerklePatriciaTree.DB.Antidote.get(db, "user_#{user_id}_#{op_id}")
        3 -> MerklePatriciaTree.DB.Antidote.delete!(db, "user_#{user_id}_#{op_id}")
      end

      operation_end = System.monotonic_time(:microsecond)
      %{
        user_id: user_id,
        operation_id: op_id,
        duration_ms: (operation_end - operation_start) / 1000
      }
    end)
  end

  defp generate_large_state_tree(size) do
    Enum.map(1..size, fn i ->
      %{
        key: "state_#{i}",
        value: generate_large_value(),
        children: generate_children(i, size)
      }
    end)
  end

  defp generate_large_value do
    :crypto.strong_rand_bytes(:rand.uniform(10000))
  end

  defp generate_children(parent_id, max_size) do
    child_count = :rand.uniform(10)
    Enum.map(1..child_count, fn child_id ->
      child_id = parent_id * 10 + child_id
      if child_id <= max_size, do: child_id, else: nil
    end)
    |> Enum.filter(&(&1 != nil))
  end

  defp load_large_state(db, large_state) do
    load_start = System.monotonic_time(:microsecond)

    Enum.each(large_state, fn state ->
      MerklePatriciaTree.DB.Antidote.put!(db, state.key, :erlang.term_to_binary(state))
    end)

    load_end = System.monotonic_time(:microsecond)
    %{
      items_loaded: length(large_state),
      load_time_ms: (load_end - load_start) / 1000,
      throughput_items_per_sec: length(large_state) / ((load_end - load_start) / 1_000_000)
    }
  end

  defp traverse_large_state(db, large_state) do
    traverse_start = System.monotonic_time(:microsecond)

    Enum.each(large_state, fn state ->
      MerklePatriciaTree.DB.Antidote.get(db, state.key)
    end)

    traverse_end = System.monotonic_time(:microsecond)
    %{
      items_traversed: length(large_state),
      traverse_time_ms: (traverse_end - traverse_start) / 1000,
      throughput_items_per_sec: length(large_state) / ((traverse_end - traverse_start) / 1_000_000)
    }
  end

  defp measure_memory_usage(db) do
    # Get memory usage information
    memory_info = :erlang.memory()
    %{
      total_mb: memory_info[:total] / 1024 / 1024,
      process_mb: memory_info[:processes] / 1024 / 1024,
      system_mb: memory_info[:system] / 1024 / 1024,
      atom_mb: memory_info[:atom] / 1024 / 1024
    }
  end

  defp test_garbage_collection(db) do
    gc_start = System.monotonic_time(:microsecond)

    # Force garbage collection
    :erlang.garbage_collect()

    gc_end = System.monotonic_time(:microsecond)
    %{
      gc_time_ms: (gc_end - gc_start) / 1000
    }
  end

  defp simulate_network_latency(db) do
    {min_latency, max_latency} = @network_latency_range

    Enum.map(1..100, fn _ ->
      latency = :rand.uniform(max_latency - min_latency) + min_latency
      :timer.sleep(latency)

      # Perform operation with simulated latency
      MerklePatriciaTree.DB.Antidote.put!(db, "latency_test_#{:rand.uniform(1000)}", "value")

      %{latency_ms: latency}
    end)
  end

  defp simulate_connection_failures(db) do
    failure_count = 0
    total_operations = 1000

    Enum.map(1..total_operations, fn _ ->
      if :rand.uniform(100) <= 5 do  # 5% failure rate
        %{status: :failed, reason: "connection_timeout"}
      else
        MerklePatriciaTree.DB.Antidote.put!(db, "failure_test_#{:rand.uniform(1000)}", "value")
        %{status: :success}
      end
    end)
    |> then(fn results ->
      failures = Enum.count(results, fn %{status: status} -> status == :failed end)
      %{
        total_operations: total_operations,
        failures: failures,
        failure_rate: failures / total_operations * 100
      }
    end)
  end

  defp simulate_node_failures(db) do
    # Simulate node failures and recovery
    Enum.map(1..10, fn failure_id ->
      failure_start = System.monotonic_time(:microsecond)

      # Simulate failure
      :timer.sleep(:rand.uniform(1000))

      # Simulate recovery
      recovery_time = :rand.uniform(5000)
      :timer.sleep(recovery_time)

      failure_end = System.monotonic_time(:microsecond)
      %{
        failure_id: failure_id,
        downtime_ms: recovery_time,
        total_time_ms: (failure_end - failure_start) / 1000
      }
    end)
  end

  defp measure_recovery_time(db) do
    recovery_times = Enum.map(1..20, fn _ ->
      recovery_start = System.monotonic_time(:microsecond)

      # Simulate recovery operation
      :timer.sleep(:rand.uniform(100))

      recovery_end = System.monotonic_time(:microsecond)
      (recovery_end - recovery_start) / 1000
    end)

    %{
      avg_ms: Enum.sum(recovery_times) / length(recovery_times),
      min_ms: Enum.min(recovery_times),
      max_ms: Enum.max(recovery_times)
    }
  end

  defp test_crdt_counters(db) do
    Enum.map(1..100, fn counter_id ->
      counter_start = System.monotonic_time(:microsecond)

      # Simulate CRDT counter operations
      MerklePatriciaTree.DB.Antidote.put!(db, "counter_#{counter_id}", :erlang.term_to_binary(0))

      # Increment counter multiple times
      Enum.each(1..10, fn increment ->
        current_value = MerklePatriciaTree.DB.Antidote.get(db, "counter_#{counter_id}")
        new_value = case current_value do
          {:ok, value} -> :erlang.binary_to_term(value) + increment
          _ -> increment
        end
        MerklePatriciaTree.DB.Antidote.put!(db, "counter_#{counter_id}", :erlang.term_to_binary(new_value))
      end)

      counter_end = System.monotonic_time(:microsecond)
      %{
        counter_id: counter_id,
        operations: 11,  # 1 put + 10 increments
        time_ms: (counter_end - counter_start) / 1000
      }
    end)
  end

  defp test_crdt_sets(db) do
    Enum.map(1..50, fn set_id ->
      set_start = System.monotonic_time(:microsecond)

      # Simulate CRDT set operations
      Enum.each(1..20, fn element ->
        MerklePatriciaTree.DB.Antidote.put!(db, "set_#{set_id}_#{element}", :erlang.term_to_binary(element))
      end)

      set_end = System.monotonic_time(:microsecond)
      %{
        set_id: set_id,
        elements: 20,
        time_ms: (set_end - set_start) / 1000
      }
    end)
  end

  defp test_crdt_maps(db) do
    Enum.map(1..25, fn map_id ->
      map_start = System.monotonic_time(:microsecond)

      # Simulate CRDT map operations
      map_data = Enum.map(1..10, fn key ->
        {key, :rand.uniform(1000)}
      end)
      |> Map.new()

      MerklePatriciaTree.DB.Antidote.put!(db, "map_#{map_id}", :erlang.term_to_binary(map_data))

      map_end = System.monotonic_time(:microsecond)
      %{
        map_id: map_id,
        keys: 10,
        time_ms: (map_end - map_start) / 1000
      }
    end)
  end

  defp test_conflict_resolution(db) do
    conflict_times = Enum.map(1..100, fn conflict_id ->
      conflict_start = System.monotonic_time(:microsecond)

      # Simulate concurrent updates to same key
      tasks = Enum.map(1..5, fn task_id ->
        Task.async(fn ->
          MerklePatriciaTree.DB.Antidote.put!(db, "conflict_#{conflict_id}", :erlang.term_to_binary(task_id))
        end)
      end)

      Task.await_many(tasks, 5000)

      conflict_end = System.monotonic_time(:microsecond)
      (conflict_end - conflict_start) / 1000
    end)

    %{
      conflicts: 100,
      avg_time_ms: Enum.sum(conflict_times) / length(conflict_times),
      min_time_ms: Enum.min(conflict_times),
      max_time_ms: Enum.max(conflict_times)
    }
  end

  defp test_memory_allocation(db) do
    allocation_start = System.monotonic_time(:microsecond)
    initial_memory = :erlang.memory()[:total]

    # Allocate large amounts of data
    Enum.each(1..10000, fn i ->
      large_data = :crypto.strong_rand_bytes(:rand.uniform(10000))
      MerklePatriciaTree.DB.Antidote.put!(db, "alloc_#{i}", large_data)
    end)

    allocation_end = System.monotonic_time(:microsecond)
    final_memory = :erlang.memory()[:total]

    %{
      items_allocated: 10000,
      allocation_time_ms: (allocation_end - allocation_start) / 1000,
      memory_increase_mb: (final_memory - initial_memory) / 1024 / 1024,
      peak_mb: final_memory / 1024 / 1024
    }
  end

  defp test_memory_cleanup(db) do
    cleanup_start = System.monotonic_time(:microsecond)
    initial_memory = :erlang.memory()[:total]

    # Delete allocated data
    Enum.each(1..10000, fn i ->
      MerklePatriciaTree.DB.Antidote.delete!(db, "alloc_#{i}")
    end)

    # Force garbage collection
    :erlang.garbage_collect()

    cleanup_end = System.monotonic_time(:microsecond)
    final_memory = :erlang.memory()[:total]

    %{
      items_cleaned: 10000,
      cleanup_time_ms: (cleanup_end - cleanup_start) / 1000,
      memory_freed_mb: (initial_memory - final_memory) / 1024 / 1024,
      efficiency_percent: ((initial_memory - final_memory) / initial_memory) * 100
    }
  end

  defp test_memory_fragmentation(db) do
    # Test memory fragmentation by allocating and deallocating in patterns
    Enum.map(1..100, fn cycle ->
      cycle_start = System.monotonic_time(:microsecond)

      # Allocate data
      Enum.each(1..100, fn i ->
        MerklePatriciaTree.DB.Antidote.put!(db, "frag_#{cycle}_#{i}", :crypto.strong_rand_bytes(:rand.uniform(1000)))
      end)

      # Delete some data
      Enum.each(1..50, fn i ->
        MerklePatriciaTree.DB.Antidote.delete!(db, "frag_#{cycle}_#{i}")
      end)

      cycle_end = System.monotonic_time(:microsecond)
      %{
        cycle: cycle,
        time_ms: (cycle_end - cycle_start) / 1000
      }
    end)
  end

  defp test_gc_under_pressure(db) do
    gc_times = Enum.map(1..50, fn gc_cycle ->
      gc_start = System.monotonic_time(:microsecond)

      # Allocate data to create pressure
      Enum.each(1..1000, fn i ->
        MerklePatriciaTree.DB.Antidote.put!(db, "gc_pressure_#{gc_cycle}_#{i}", :crypto.strong_rand_bytes(:rand.uniform(100)))
      end)

      # Force garbage collection
      :erlang.garbage_collect()

      gc_end = System.monotonic_time(:microsecond)
      (gc_end - gc_start) / 1000
    end)

    %{
      gc_cycles: 50,
      avg_gc_time_ms: Enum.sum(gc_times) / length(gc_times),
      max_gc_time_ms: Enum.max(gc_times)
    }
  end

  defp test_read_heavy_workload(db) do
    # 80% reads, 20% writes
    Enum.map(1..1000, fn op_id ->
      op_start = System.monotonic_time(:microsecond)

      case :rand.uniform(100) do
        x when x <= 80 ->
          # Read operation
          MerklePatriciaTree.DB.Antidote.get(db, "read_heavy_#{:rand.uniform(1000)}")
        _ ->
          # Write operation
          MerklePatriciaTree.DB.Antidote.put!(db, "read_heavy_#{op_id}", "value_#{op_id}")
      end

      op_end = System.monotonic_time(:microsecond)
      %{
        operation_id: op_id,
        type: if(:rand.uniform(100) <= 80, do: :read, else: :write),
        time_ms: (op_end - op_start) / 1000
      }
    end)
  end

  defp test_write_heavy_workload(db) do
    # 20% reads, 80% writes
    Enum.map(1..1000, fn op_id ->
      op_start = System.monotonic_time(:microsecond)

      case :rand.uniform(100) do
        x when x <= 20 ->
          # Read operation
          MerklePatriciaTree.DB.Antidote.get(db, "write_heavy_#{:rand.uniform(1000)}")
        _ ->
          # Write operation
          MerklePatriciaTree.DB.Antidote.put!(db, "write_heavy_#{op_id}", "value_#{op_id}")
      end

      op_end = System.monotonic_time(:microsecond)
      %{
        operation_id: op_id,
        type: if(:rand.uniform(100) <= 20, do: :read, else: :write),
        time_ms: (op_end - op_start) / 1000
      }
    end)
  end

  defp test_balanced_workload(db) do
    # 50% reads, 50% writes
    Enum.map(1..1000, fn op_id ->
      op_start = System.monotonic_time(:microsecond)

      case :rand.uniform(100) do
        x when x <= 50 ->
          # Read operation
          MerklePatriciaTree.DB.Antidote.get(db, "balanced_#{:rand.uniform(1000)}")
        _ ->
          # Write operation
          MerklePatriciaTree.DB.Antidote.put!(db, "balanced_#{op_id}", "value_#{op_id}")
      end

      op_end = System.monotonic_time(:microsecond)
      %{
        operation_id: op_id,
        type: if(:rand.uniform(100) <= 50, do: :read, else: :write),
        time_ms: (op_end - op_start) / 1000
      }
    end)
  end

  defp test_burst_traffic(db) do
    # Simulate burst traffic patterns
    Enum.map(1..10, fn burst_id ->
      burst_start = System.monotonic_time(:microsecond)

      # Create burst of operations
      tasks = Enum.map(1..100, fn op_id ->
        Task.async(fn ->
          MerklePatriciaTree.DB.Antidote.put!(db, "burst_#{burst_id}_#{op_id}", "value_#{op_id}")
        end)
      end)

      Task.await_many(tasks, 5000)

      burst_end = System.monotonic_time(:microsecond)
      %{
        burst_id: burst_id,
        operations: 100,
        time_ms: (burst_end - burst_start) / 1000
      }
    end)
  end

  # Helper functions for counting and calculations

  defp count_operations(results) do
    results.block_processing
    |> Enum.map(fn %{transactions: tx_count} -> tx_count end)
    |> Enum.sum()
  end

  defp count_crdt_operations(results) do
    results.counter_operations
    |> Enum.map(fn %{operations: ops} -> ops end)
    |> Enum.sum()
  end

  defp count_mixed_operations(results) do
    length(results.read_heavy) + length(results.write_heavy) + length(results.balanced) +
    (results.burst_traffic |> Enum.map(fn %{operations: ops} -> ops end) |> Enum.sum())
  end

  defp calculate_avg_latency(results) do
    all_operations = results.read_heavy ++ results.write_heavy ++ results.balanced

    total_time = all_operations
    |> Enum.map(fn %{time_ms: time} -> time end)
    |> Enum.sum()

    total_time / length(all_operations)
  end

  defp generate_load_test_report(results) do
    IO.puts("\n📊 Load & Stress Test Report")
    IO.puts("=" |> String.duplicate(60))

    Enum.each(results, fn {scenario, data} ->
      IO.puts("\n🎯 #{String.upcase(scenario)}")
      IO.puts("Duration: #{data.duration_ms}ms")
      IO.puts("Throughput: #{data.throughput_ops_per_sec} ops/sec")

      case scenario do
        :high_concurrency ->
          IO.puts("Concurrent Users: #{data.concurrent_users}")
          IO.puts("Operations per User: #{data.operations_per_user}")
        :large_state_operations ->
          IO.puts("State Size: #{data.state_size} items")
          IO.puts("Memory Usage: #{data.memory_usage_mb} MB")
        :network_stress ->
          IO.puts("Failure Rate: #{data.failure_rate}%")
          IO.puts("Avg Recovery Time: #{data.avg_recovery_time_ms}ms")
        :crdt_performance ->
          IO.puts("CRDT Operations: #{data.crdt_operations}")
          IO.puts("Conflict Resolution Time: #{data.conflict_resolution_time_ms}ms")
        :memory_pressure ->
          IO.puts("Peak Memory: #{data.peak_memory_mb} MB")
          IO.puts("Memory Efficiency: #{data.memory_efficiency}%")
        :mixed_workload ->
          IO.puts("Total Operations: #{data.total_operations}")
          IO.puts("Avg Latency: #{data.avg_latency_ms}ms")
        _ ->
          IO.puts("Operations: #{data.operations}")
      end
    end)

    IO.puts("\n✅ Load & Stress Testing Complete!")
  end
end
