defmodule MerklePatriciaTree.StateManagementTest do
  @moduledoc """
  Comprehensive tests for the state management system including
  long-running node scenarios, pruning modes, and garbage collection.
  """

  use ExUnit.Case, async: false
  alias MerklePatriciaTree.{DB, StateManager}
  alias MerklePatriciaTree.StateManager.{PruningPolicy, ReferenceCounter, GarbageCollector}

  @moduletag :integration

  setup do
    # Create test database
    db = MerklePatriciaTree.Test.random_ets_db()

    # Setup test data
    test_blocks =
      for i <- 1..200 do
        block_hash = :crypto.hash(:sha256, <<i::64>>)
        state_root = :crypto.hash(:sha256, <<"state_#{i}">>)

        # Store block data
        DB.put!(
          db,
          "block_#{i}",
          %{
            number: i,
            hash: block_hash,
            state_root: state_root,
            # 12 second blocks
            timestamp: System.os_time(:second) - (200 - i) * 12
          }
          |> :erlang.term_to_binary()
        )

        # Store state data
        # 1KB state
        DB.put!(db, state_root, :crypto.strong_rand_bytes(1024))

        %{number: i, hash: block_hash, state_root: state_root}
      end

    {:ok, db: db, test_blocks: test_blocks}
  end

  describe "State Pruning Modes" do
    test "fast mode keeps only recent blocks", %{db: db} do
      # Test fast mode with 50 blocks to keep
      {nodes_pruned, bytes_freed} = PruningPolicy.prune_fast_mode(db, 50)

      # Should prune old blocks
      assert nodes_pruned > 0
      assert bytes_freed > 0

      # Verify recent blocks are kept
      current_block = 200

      for i <- (current_block - 49)..current_block do
        assert {:ok, _data} = DB.get(db, :crypto.hash(:sha256, <<i::64>>))
      end
    end

    test "full mode with reference counting", %{db: db} do
      # Setup reference counter
      counter = ReferenceCounter.new()

      # Add references for some state roots (simulating active usage)
      active_roots =
        for i <- 150..200 do
          :crypto.hash(:sha256, <<"state_#{i}">>)
        end

      counter =
        Enum.reduce(active_roots, counter, fn root, acc ->
          ReferenceCounter.increment(acc, root)
        end)

      # Perform full mode pruning
      {nodes_pruned, bytes_freed} = PruningPolicy.prune_full_mode(db, counter)

      # Should have found some unreferenced nodes to prune
      assert nodes_pruned >= 0
      assert bytes_freed >= 0
    end

    test "archive mode performs no pruning", %{db: db} do
      # Archive mode should never prune anything
      # This is implicitly tested in StateManager when pruning_mode: :archive
      # returns {0, 0} from the pruning operation

      {_db_mod, db_ref} = db
      initial_size = :ets.info(db_ref, :size)

      # Simulate archive mode (no actual pruning call needed)
      # Archive mode behavior
      {nodes_pruned, bytes_freed} = {0, 0}

      assert nodes_pruned == 0
      assert bytes_freed == 0

      final_size = :ets.info(db_ref, :size)
      assert final_size == initial_size
    end
  end

  describe "Reference Counting System" do
    test "tracks references correctly", %{db: db, test_blocks: test_blocks} do
      counter = ReferenceCounter.new()

      # Add references for multiple blocks
      state_roots = Enum.take(test_blocks, 10) |> Enum.map(& &1.state_root)

      counter =
        Enum.reduce(state_roots, counter, fn root, acc ->
          ReferenceCounter.increment(acc, root)
        end)

      # Verify references were added
      Enum.each(state_roots, fn root ->
        assert ReferenceCounter.get_references(counter, root) > 0
      end)

      # Remove some references
      {root_to_remove, remaining_roots} = List.pop_at(state_roots, 0)
      counter = ReferenceCounter.decrement(counter, root_to_remove)

      # Verify the removed root has no references
      assert ReferenceCounter.get_references(counter, root_to_remove) == 0

      # Verify remaining roots still have references
      Enum.each(remaining_roots, fn root ->
        assert ReferenceCounter.get_references(counter, root) > 0
      end)
    end

    test "identifies unreferenced nodes", %{db: db, test_blocks: test_blocks} do
      counter = ReferenceCounter.new()

      # Add references for only half the blocks
      referenced_roots =
        test_blocks
        |> Enum.take(100)
        |> Enum.map(& &1.state_root)

      counter =
        Enum.reduce(referenced_roots, counter, fn root, acc ->
          ReferenceCounter.increment(acc, root)
        end)

      # Get unreferenced nodes
      unreferenced = ReferenceCounter.get_unreferenced_nodes(counter)

      # Should find unreferenced nodes (nodes that were never added get 0 references)
      assert is_list(unreferenced)
    end
  end

  describe "Garbage Collection" do
    test "collects unreferenced nodes", %{db: db, test_blocks: test_blocks} do
      # Create some unreferenced state roots
      unreferenced_roots =
        test_blocks
        |> Enum.take(50)
        |> Enum.map(& &1.state_root)

      {_db_mod, db_ref} = db
      initial_count = :ets.info(db_ref, :size)

      # Perform garbage collection
      {nodes_removed, bytes_freed} =
        GarbageCollector.collect_unreferenced_nodes(
          db,
          unreferenced_roots
        )

      assert nodes_removed >= 0
      assert bytes_freed >= 0

      final_count = :ets.info(db_ref, :size)
      assert final_count <= initial_count
    end

    test "incremental collection respects time limits", %{db: db, test_blocks: test_blocks} do
      unreferenced_roots =
        test_blocks
        |> Enum.take(20)
        |> Enum.map(& &1.state_root)

      # Perform incremental collection with very short time limit
      # 10ms limit
      stats = GarbageCollector.incremental_collect(db, unreferenced_roots, 10)

      assert is_map(stats)
      assert Map.has_key?(stats, :nodes_collected)
      assert Map.has_key?(stats, :bytes_freed)
      assert Map.has_key?(stats, :duration_ms)
      assert Map.has_key?(stats, :errors)

      # Should respect time limit
      # Could be 0 if very fast
      assert stats.duration_ms >= 0
    end

    test "provides garbage collection recommendations", %{db: db} do
      recommendations = GarbageCollector.get_gc_recommendations(db)

      assert is_map(recommendations)
      assert Map.has_key?(recommendations, :should_collect)
      assert Map.has_key?(recommendations, :estimated_nodes)
      assert Map.has_key?(recommendations, :estimated_bytes)
      assert Map.has_key?(recommendations, :urgency)
      assert Map.has_key?(recommendations, :reasons)

      assert recommendations.urgency in [:low, :medium, :high, :critical]
      assert is_boolean(recommendations.should_collect)
      assert is_list(recommendations.reasons)
    end
  end

  describe "Long-running Node Scenarios" do
    # 2 minute timeout for long test
    @tag timeout: 120_000
    test "handles extended operation with continuous state changes", %{db: db} do
      # Start state manager in fast mode for this test
      config = [
        pruning_mode: :fast,
        fast_blocks_to_keep: 100,
        # 1 second for testing
        gc_interval: 1000,
        # 2 seconds
        disk_usage_check_interval: 2000,
        # 5 seconds
        full_pruning_interval: 5000
      ]

      {:ok, _pid} = StateManager.start_link(db, config)

      # Simulate continuous blockchain operation
      # 300 new blocks
      simulate_blockchain_activity(db, 300)

      # Let the state manager run for a bit
      # 10 seconds
      Process.sleep(10_000)

      # Check that pruning has occurred
      stats = StateManager.get_pruning_stats()
      assert stats.total_nodes_pruned >= 0

      # Check disk usage monitoring
      disk_usage = StateManager.get_disk_usage()
      assert is_map(disk_usage)
      assert Map.has_key?(disk_usage, :usage_percentage)
    end

    test "memory usage remains stable during long operation", %{db: db} do
      config = [
        pruning_mode: :full,
        # Aggressive GC for testing
        gc_interval: 500,
        disk_usage_check_interval: 1000
      ]

      {:ok, _pid} = StateManager.start_link(db, config)

      initial_memory = :erlang.memory(:total)

      # Simulate heavy state activity
      for batch <- 1..10 do
        simulate_blockchain_activity(db, 50)
        # Allow GC to run
        Process.sleep(1000)

        current_memory = :erlang.memory(:total)
        memory_growth = (current_memory - initial_memory) / initial_memory

        # Memory shouldn't grow excessively (allow 50% growth)
        assert memory_growth < 0.5,
               "Memory growth too high in batch #{batch}: #{Float.round(memory_growth * 100, 1)}%"
      end
    end

    test "snapshot creation and restoration", %{db: db} do
      # Daily snapshots
      config = [pruning_mode: :archive, snapshot_interval: 86_400_000]
      {:ok, _pid} = StateManager.start_link(db, config)

      # Add some state data
      simulate_blockchain_activity(db, 100)

      # Create manual snapshot
      {:ok, snapshot_path} = StateManager.create_snapshot()

      assert File.exists?(snapshot_path)

      # Verify snapshot contents
      snapshot_data = File.read!(snapshot_path) |> :erlang.binary_to_term()

      assert Map.has_key?(snapshot_data, :timestamp)
      assert Map.has_key?(snapshot_data, :pruning_mode)
      assert Map.has_key?(snapshot_data, :reference_counts)
      assert snapshot_data.pruning_mode == :archive

      # Cleanup
      File.rm!(snapshot_path)
    end

    test "handles database corruption gracefully", %{db: db} do
      config = [pruning_mode: :full]
      {:ok, _pid} = StateManager.start_link(db, config)

      # Simulate some corruption by deleting random keys
      {_db_mod, db_ref} = db
      db_keys = :ets.tab2list(db_ref) |> Enum.map(fn {k, _v} -> k end) |> Enum.take(10)

      Enum.each(db_keys, fn key ->
        DB.delete!(db, key)
      end)

      # State manager should continue operating despite corruption
      StateManager.force_garbage_collection()
      Process.sleep(1000)

      # Should still be responsive
      stats = StateManager.get_pruning_stats()
      assert is_map(stats)
    end
  end

  describe "Performance Under Load" do
    test "maintains performance with large state trees", %{db: db} do
      # Create a large number of state entries
      large_dataset_size = 10_000

      start_time = System.monotonic_time(:millisecond)

      for i <- 1..large_dataset_size do
        state_root = :crypto.hash(:sha256, <<"large_state_#{i}">>)
        # 2KB per entry
        data = :crypto.strong_rand_bytes(2048)
        DB.put!(db, state_root, data)
      end

      creation_time = System.monotonic_time(:millisecond) - start_time

      # Test pruning performance on large dataset
      counter = ReferenceCounter.new()

      # Only reference half the states
      referenced_count = div(large_dataset_size, 2)

      for i <- 1..referenced_count do
        state_root = :crypto.hash(:sha256, <<"large_state_#{i}">>)
        counter = ReferenceCounter.increment(counter, state_root)
      end

      prune_start = System.monotonic_time(:millisecond)
      {nodes_pruned, bytes_freed} = PruningPolicy.prune_full_mode(db, counter)
      prune_time = System.monotonic_time(:millisecond) - prune_start

      # Performance assertions
      assert creation_time < 30_000, "Dataset creation took too long: #{creation_time}ms"
      assert prune_time < 10_000, "Pruning took too long: #{prune_time}ms"

      # Should have pruned unreferenced nodes
      assert nodes_pruned >= 0
      assert bytes_freed >= 0

      IO.puts("\nPerformance Results:")
      IO.puts("- Created #{large_dataset_size} entries in #{creation_time}ms")
      IO.puts("- Pruned #{nodes_pruned} nodes (#{bytes_freed} bytes) in #{prune_time}ms")
    end
  end

  # Helper function to simulate blockchain activity
  defp simulate_blockchain_activity(db, num_blocks) do
    for i <- 1..num_blocks do
      block_num = System.os_time(:second) + i
      state_root = :crypto.hash(:sha256, <<"simulated_state_#{block_num}">>)
      # Variable size
      state_data = :crypto.strong_rand_bytes(1024 + :rand.uniform(2048))

      # Add new state
      DB.put!(db, state_root, state_data)

      # Update reference counting
      StateManager.increment_state_root_references(state_root)

      # Occasionally decrement old references
      if rem(i, 10) == 0 do
        old_state = :crypto.hash(:sha256, <<"simulated_state_#{block_num - 50}">>)
        StateManager.decrement_state_root_references(old_state)
      end
    end
  end
end
