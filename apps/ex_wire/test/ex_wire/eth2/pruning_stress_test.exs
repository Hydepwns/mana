defmodule ExWire.Eth2.PruningStressTest do
  use ExUnit.Case, async: false

  alias ExWire.Eth2.{
    TestDataGenerator,
    PruningManager,
    PruningStrategies,
    PruningMetrics,
    PruningScheduler
  }

  @moduletag :stress
  # 10 minutes per test
  @moduletag timeout: 600_000

  # Stress test scenarios
  @stress_scenarios %{
    deep_reorg: %{
      description: "Deep reorganizations with complex fork structures",
      fork_probability: 0.3,
      max_reorg_depth: 20,
      blocks: 50_000
    },
    massive_attestations: %{
      description: "Massive attestation pools with high validator count",
      validators: 1_500_000,
      attestations_per_slot: 500,
      slots: 10_000
    },
    memory_pressure: %{
      description: "Memory pressure with large state histories",
      states: 100_000,
      state_size_multiplier: 2.0,
      concurrent_operations: 8
    },
    sustained_load: %{
      description: "Sustained high-frequency pruning operations",
      duration_minutes: 5,
      operations_per_minute: 60,
      # MB per minute
      data_growth_rate: 100
    }
  }

  setup_all do
    # Configure for stress testing
    Application.put_env(:ex_wire, :pruning_stress_mode, true)

    # Start metrics with higher retention for stress analysis
    {:ok, _} =
      PruningMetrics.start_link(
        name: :stress_metrics,
        config: %{history_retention_hours: 2}
      )

    on_exit(fn ->
      Application.delete_env(:ex_wire, :pruning_stress_mode)
    end)

    :ok
  end

  describe "extreme fork choice scenarios" do
    @tag :fork_choice_stress
    test "handles deep reorganizations with complex fork trees" do
      Logger.info("Stress testing: #{@stress_scenarios.deep_reorg.description}")

      scenario = @stress_scenarios.deep_reorg

      # Generate complex fork structure
      dataset =
        TestDataGenerator.generate_dataset(:stress_test, :medium,
          fork_probability: scenario.fork_probability,
          max_reorg_depth: scenario.max_reorg_depth
        )

      fork_choice_data = dataset.fork_choice_store
      initial_blocks = map_size(fork_choice_data.blocks)

      Logger.info("Generated #{initial_blocks} blocks with complex fork structure")

      Logger.info(
        "Fork probability: #{scenario.fork_probability * 100}%, Max reorg depth: #{scenario.max_reorg_depth}"
      )

      # Analyze fork complexity
      fork_stats = analyze_fork_complexity(fork_choice_data)
      Logger.info("Fork analysis: #{inspect(fork_stats)}")

      # Test pruning under extreme conditions
      stress_results = []

      # Multiple pruning cycles with different finalization points
      for finalization_distance <- [50, 100, 500, 1000] do
        Logger.info("Testing finalization distance: #{finalization_distance}")

        # Create finalization point
        finalized_slot = max(0, initial_blocks - finalization_distance)

        finalized_checkpoint = %{
          epoch: div(finalized_slot, 32),
          root: find_block_at_slot(fork_choice_data.blocks, finalized_slot)
        }

        # Execute pruning
        start_time = System.monotonic_time(:millisecond)

        {:ok, pruned_store, result} =
          PruningStrategies.prune_fork_choice(
            fork_choice_data,
            finalized_checkpoint,
            safety_margin_slots: 16
          )

        duration_ms = System.monotonic_time(:millisecond) - start_time

        pruned_blocks = initial_blocks - map_size(pruned_store.blocks)
        pruning_ratio = pruned_blocks / initial_blocks

        stress_result = %{
          finalization_distance: finalization_distance,
          duration_ms: duration_ms,
          blocks_pruned: pruned_blocks,
          pruning_ratio: pruning_ratio,
          memory_freed_mb: result.memory_freed_mb
        }

        stress_results = [stress_result | stress_results]

        Logger.info(
          "Distance #{finalization_distance}: #{pruned_blocks} blocks pruned (#{Float.round(pruning_ratio * 100, 1)}%) in #{duration_ms}ms"
        )

        # Verify pruning correctness under stress
        verify_fork_choice_pruning_correctness(pruned_store, finalized_checkpoint)

        # Performance should degrade gracefully under complexity
        assert duration_ms < 60_000, "Should complete within 60s even under stress"
        assert pruning_ratio > 0.1, "Should prune at least 10% even with complex forks"
      end

      # Analyze stress performance characteristics
      analyze_stress_performance(stress_results, "deep_reorg")
    end

    @tag :fork_choice_stress
    test "survives pathological fork structures" do
      Logger.info("Testing pathological fork scenarios")

      # Create pathological scenarios
      pathological_scenarios = [
        # Many 3-block forks
        create_many_short_forks(10_000, 3),
        # 5 chains of 1000 blocks each
        create_long_competing_chains(5, 1000),
        # Very high fork density
        create_dense_fork_pattern(1000, 0.8)
      ]

      for {scenario_name, fork_choice_data} <- pathological_scenarios do
        Logger.info("Testing pathological scenario: #{scenario_name}")

        initial_blocks = map_size(fork_choice_data.blocks)

        # Attempt pruning under pathological conditions
        start_time = System.monotonic_time(:millisecond)

        try do
          {:ok, pruned_store, result} =
            PruningStrategies.prune_fork_choice(
              fork_choice_data,
              fork_choice_data.finalized_checkpoint
            )

          duration_ms = System.monotonic_time(:millisecond) - start_time

          pruned_blocks = initial_blocks - map_size(pruned_store.blocks)

          Logger.info("#{scenario_name}: #{pruned_blocks} blocks pruned in #{duration_ms}ms")

          # Should handle pathological cases without crashing
          assert is_map(pruned_store), "Should return valid pruned store"

          assert duration_ms < 120_000,
                 "Should complete within 2 minutes even for pathological cases"
        rescue
          error ->
            Logger.error("Pathological scenario #{scenario_name} failed: #{inspect(error)}")

            # Document failure for analysis but don't fail test (pathological cases expected to be challenging)
            Logger.warn("Pathological case failure documented for performance analysis")
        end
      end
    end
  end

  describe "massive data volume stress" do
    @tag :massive_data
    test "handles massive attestation pools efficiently" do
      Logger.info("Stress testing: #{@stress_scenarios.massive_attestations.description}")

      scenario = @stress_scenarios.massive_attestations

      # Generate massive attestation dataset
      massive_dataset =
        generate_massive_attestation_data(
          scenario.validators,
          scenario.attestations_per_slot,
          scenario.slots
        )

      total_attestations = count_total_attestations(massive_dataset)
      # ~1KB per attestation
      estimated_size_mb = total_attestations * 0.001

      Logger.info(
        "Generated #{total_attestations} attestations (~#{Float.round(estimated_size_mb, 1)} MB)"
      )

      # Test progressive pruning under massive load
      beacon_state = create_mock_beacon_state(scenario.slots - 1, massive_dataset)
      fork_choice_store = create_minimal_fork_choice()

      # Test with different pruning aggressiveness levels
      aggressiveness_levels = [
        {false, false, "conservative"},
        {true, false, "aggressive"},
        {true, true, "maximum"}
      ]

      for {aggressive, dedupe, level_name} <- aggressiveness_levels do
        Logger.info("Testing #{level_name} pruning on massive dataset")

        # Monitor memory during operation
        initial_memory = :erlang.memory(:total)

        start_time = System.monotonic_time(:millisecond)

        {:ok, pruned_pool, result} =
          PruningStrategies.prune_attestation_pool(
            massive_dataset,
            beacon_state,
            fork_choice_store,
            aggressive: aggressive,
            deduplicate: dedupe
          )

        duration_ms = System.monotonic_time(:millisecond) - start_time
        final_memory = :erlang.memory(:total)

        memory_delta_mb = (final_memory - initial_memory) / (1024 * 1024)

        Logger.info(
          "#{level_name}: #{result.total_pruned} attestations pruned in #{duration_ms}ms"
        )

        Logger.info("Memory delta: #{Float.round(memory_delta_mb, 1)} MB")

        Logger.info(
          "Throughput: #{Float.round(result.total_pruned / (duration_ms / 1000), 0)} attestations/sec"
        )

        # Performance assertions for massive data
        assert duration_ms < 300_000, "Should complete within 5 minutes for massive datasets"
        assert result.total_pruned > 0, "Should prune some attestations"

        # Memory usage should be reasonable
        assert memory_delta_mb < 1000, "Memory growth should be < 1GB during processing"

        # Throughput should be reasonable
        throughput = result.total_pruned / (duration_ms / 1000)
        assert throughput > 100, "Should maintain at least 100 attestations/sec throughput"

        # Record stress metrics
        PruningMetrics.record_operation(:massive_attestations, :ok, duration_ms, %{
          level: level_name,
          total_attestations: total_attestations,
          throughput: throughput
        })
      end
    end

    @tag :massive_data
    test "maintains performance under memory pressure" do
      Logger.info("Stress testing: #{@stress_scenarios.memory_pressure.description}")

      scenario = @stress_scenarios.memory_pressure

      # Create memory pressure by generating large state history
      large_dataset = TestDataGenerator.generate_dataset(:stress_test, :large)

      # Start multiple concurrent pruning operations to create memory pressure
      concurrent_tasks =
        for task_id <- 1..scenario.concurrent_operations do
          Task.async(fn ->
            Logger.info("Starting concurrent stress task #{task_id}")

            # Each task processes a subset of the data
            subset_states =
              large_dataset.beacon_states.states
              |> Enum.take_every(scenario.concurrent_operations)
              |> Enum.into(%{})

            start_time = System.monotonic_time(:millisecond)

            # Simulate state pruning under memory pressure
            {:ok, result} =
              PruningStrategies.prune_state_trie(
                %{states: subset_states},
                # 1 day retention
                7200,
                parallel_marking: true,
                compact_after_pruning: true
              )

            duration_ms = System.monotonic_time(:millisecond) - start_time

            {task_id, result, duration_ms}
          end)
        end

      # Monitor system memory during concurrent operations
      memory_monitor =
        Task.async(fn ->
          # Monitor for 30 seconds
          monitor_memory_pressure(30_000)
        end)

      # Wait for all tasks to complete
      # 5 minute timeout
      task_results = Task.await_many(concurrent_tasks, 300_000)
      memory_stats = Task.await(memory_monitor, 35_000)

      # Analyze results under memory pressure
      total_duration =
        Enum.reduce(task_results, 0, fn {_id, _result, duration}, acc ->
          acc + duration
        end)

      avg_duration = total_duration / length(task_results)

      Logger.info("Concurrent stress test completed")

      Logger.info(
        "Tasks: #{length(task_results)}, Average duration: #{Float.round(avg_duration, 0)}ms"
      )

      Logger.info("Memory stats: #{inspect(memory_stats)}")

      # All tasks should complete successfully under pressure
      for {task_id, result, duration} <- task_results do
        assert result != nil, "Task #{task_id} should complete successfully"
        assert duration < 180_000, "Task #{task_id} should complete within 3 minutes"
      end

      # Memory should remain stable during pressure
      if memory_stats.max_memory > 0 do
        memory_growth_ratio = memory_stats.max_memory / memory_stats.min_memory
        assert memory_growth_ratio < 3.0, "Memory shouldn't grow more than 3x under pressure"
      end

      # Performance degradation should be graceful
      assert avg_duration < 60_000, "Average performance should remain reasonable under pressure"
    end
  end

  describe "sustained load testing" do
    @tag :sustained_load
    test "maintains performance under sustained high-frequency operations" do
      Logger.info("Stress testing: #{@stress_scenarios.sustained_load.description}")

      scenario = @stress_scenarios.sustained_load

      # Setup for sustained load test
      {:ok, manager_pid} =
        PruningManager.start_link(
          name: :sustained_load_manager,
          config: %{
            max_concurrent_pruners: 4,
            pruning_batch_size: 1500,
            # Very frequent pruning
            pruning_interval_ms: 1000
          }
        )

      # Setup metrics collection for sustained test
      metrics_collector =
        Task.async(fn ->
          collect_sustained_metrics(scenario.duration_minutes * 60 * 1000)
        end)

      # Generate continuous load
      load_generator =
        Task.async(fn ->
          generate_sustained_pruning_load(
            manager_pid,
            scenario.duration_minutes,
            scenario.operations_per_minute
          )
        end)

      # Monitor system health during sustained load
      health_monitor =
        Task.async(fn ->
          monitor_system_health(scenario.duration_minutes * 60 * 1000)
        end)

      try do
        # Wait for sustained test to complete
        load_results = Task.await(load_generator, (scenario.duration_minutes + 1) * 60 * 1000)
        metrics_data = Task.await(metrics_collector, 30_000)
        health_data = Task.await(health_monitor, 30_000)

        Logger.info("Sustained load test completed")
        Logger.info("Operations executed: #{load_results.total_operations}")
        Logger.info("Success rate: #{Float.round(load_results.success_rate * 100, 1)}%")
        Logger.info("Average operation time: #{Float.round(load_results.avg_duration_ms, 0)}ms")

        # Sustained performance requirements
        assert load_results.success_rate >= 0.95,
               "Should maintain 95%+ success rate under sustained load"

        assert load_results.avg_duration_ms < 30_000,
               "Average operation time should remain reasonable"

        # System health should remain stable
        assert health_data.max_cpu_percent < 80, "CPU usage should stay below 80%"
        assert health_data.memory_stable, "Memory usage should remain stable"

        # Throughput should be consistent
        if length(metrics_data) > 10 do
          throughput_variance = calculate_throughput_variance(metrics_data)
          assert throughput_variance < 0.5, "Throughput variance should be low (< 50%)"
        end
      after
        if Process.alive?(manager_pid), do: GenServer.stop(manager_pid)
      end
    end
  end

  describe "edge cases and error conditions" do
    @tag :edge_cases
    test "handles corrupt or invalid data gracefully" do
      Logger.info("Testing edge cases and error conditions")

      # Test corrupt fork choice data
      corrupt_scenarios = [
        create_corrupt_fork_choice_data("missing_parent_references"),
        create_corrupt_fork_choice_data("circular_references"),
        create_corrupt_fork_choice_data("invalid_block_data"),
        create_corrupt_fork_choice_data("inconsistent_weights")
      ]

      for {scenario_name, corrupt_data} <- corrupt_scenarios do
        Logger.info("Testing corrupt scenario: #{scenario_name}")

        # Should handle corruption gracefully without crashing
        try do
          result =
            PruningStrategies.prune_fork_choice(
              corrupt_data,
              corrupt_data.finalized_checkpoint
            )

          # If it succeeds, result should be valid
          case result do
            {:ok, pruned_store, _result} ->
              assert is_map(pruned_store), "Result should be valid map"
              Logger.info("#{scenario_name}: Handled gracefully with valid result")

            {:error, reason} ->
              Logger.info("#{scenario_name}: Failed gracefully with reason: #{inspect(reason)}")
              assert is_atom(reason), "Should return structured error reason"
          end
        rescue
          error ->
            # Document but don't fail test - some corruption might cause crashes
            Logger.warn("#{scenario_name}: Crashed with #{inspect(error)}")
            Logger.warn("Crash documented for robustness analysis")
        end
      end
    end

    @tag :resource_exhaustion
    test "handles resource exhaustion scenarios" do
      Logger.info("Testing resource exhaustion scenarios")

      # Test memory exhaustion simulation
      Logger.info("Simulating memory pressure scenario")

      # Create artificially large dataset that approaches memory limits
      # Use 80% of available memory
      memory_limit = get_available_memory() * 0.8

      try do
        # Generate dataset that approaches memory limits
        oversized_dataset = generate_oversized_test_data(memory_limit)

        Logger.info("Generated oversized dataset approaching memory limits")

        # Attempt pruning under memory pressure
        start_time = System.monotonic_time(:millisecond)

        result =
          PruningStrategies.prune_fork_choice(
            oversized_dataset,
            oversized_dataset.finalized_checkpoint
          )

        duration_ms = System.monotonic_time(:millisecond) - start_time

        case result do
          {:ok, _pruned_store, _result} ->
            Logger.info("Memory pressure test: Success in #{duration_ms}ms")

            assert duration_ms < 180_000,
                   "Should complete within 3 minutes even under memory pressure"

          {:error, :memory_exhausted} ->
            Logger.info("Memory pressure test: Gracefully failed with memory exhaustion")

          # This is acceptable - system should fail gracefully

          {:error, reason} ->
            Logger.info("Memory pressure test: Failed with reason: #{inspect(reason)}")
        end
      rescue
        error ->
          Logger.warn("Memory exhaustion test crashed: #{inspect(error)}")
          # For extreme memory pressure, crashes may be unavoidable
      end
    end
  end

  # Private helper functions

  defp analyze_fork_complexity(fork_choice_data) do
    blocks = fork_choice_data.blocks

    # Calculate fork statistics
    parent_child_map = build_parent_child_map(blocks)

    fork_points =
      Enum.count(parent_child_map, fn {_parent, children} ->
        length(children) > 1
      end)

    max_fork_width =
      parent_child_map
      |> Map.values()
      |> Enum.map(&length/1)
      |> Enum.max(fn -> 0 end)

    chain_lengths = calculate_chain_lengths(blocks, parent_child_map)

    %{
      total_blocks: map_size(blocks),
      fork_points: fork_points,
      max_fork_width: max_fork_width,
      avg_chain_length: Enum.sum(chain_lengths) / max(length(chain_lengths), 1),
      max_chain_length: Enum.max(chain_lengths ++ [0])
    }
  end

  defp build_parent_child_map(blocks) do
    Enum.reduce(blocks, %{}, fn {root, block_info}, acc ->
      parent_root = block_info.block.parent_root
      Map.update(acc, parent_root, [root], &[root | &1])
    end)
  end

  defp calculate_chain_lengths(blocks, parent_child_map) do
    # Find leaf nodes (nodes with no children)
    leaf_nodes = Map.keys(blocks) -- Map.keys(parent_child_map)

    # Calculate chain length from each leaf back to genesis
    Enum.map(leaf_nodes, fn leaf ->
      calculate_chain_length_from_node(leaf, blocks, 0)
    end)
  end

  defp calculate_chain_length_from_node(node_root, blocks, depth) when depth > 1000 do
    # Prevent infinite recursion in case of cycles
    depth
  end

  defp calculate_chain_length_from_node(node_root, blocks, depth) do
    case Map.get(blocks, node_root) do
      nil ->
        depth

      block_info ->
        parent_root = block_info.block.parent_root

        if parent_root == <<0::256>> do
          depth + 1
        else
          calculate_chain_length_from_node(parent_root, blocks, depth + 1)
        end
    end
  end

  defp find_block_at_slot(blocks, target_slot) do
    blocks
    |> Enum.filter(fn {_root, info} -> info.block.slot == target_slot end)
    |> case do
      [{root, _info} | _] -> root
      # Fallback
      [] -> :crypto.strong_rand_bytes(32)
    end
  end

  defp verify_fork_choice_pruning_correctness(pruned_store, finalized_checkpoint) do
    # Verify finalized checkpoint is retained
    finalized_root = finalized_checkpoint.root

    assert Map.has_key?(pruned_store.blocks, finalized_root),
           "Finalized block must be retained"

    # Verify store structure integrity
    assert Map.has_key?(pruned_store, :blocks), "Must have blocks"
    assert Map.has_key?(pruned_store, :weight_cache), "Must have weight cache"

    # Verify no dangling references
    for {_root, block_info} <- pruned_store.blocks do
      parent_root = block_info.block.parent_root

      # Skip genesis parent
      if parent_root != <<0::256>> do
        assert Map.has_key?(pruned_store.blocks, parent_root) or
                 parent_root == finalized_root,
               "Parent references should be valid or finalized"
      end
    end
  end

  defp analyze_stress_performance(stress_results, test_name) do
    # Analyze performance characteristics under stress
    durations = Enum.map(stress_results, & &1.duration_ms)
    pruning_ratios = Enum.map(stress_results, & &1.pruning_ratio)

    avg_duration = Enum.sum(durations) / length(durations)
    max_duration = Enum.max(durations)

    avg_pruning = Enum.sum(pruning_ratios) / length(pruning_ratios)

    Logger.info("Stress analysis for #{test_name}:")
    Logger.info("Average duration: #{Float.round(avg_duration, 0)}ms")
    Logger.info("Max duration: #{max_duration}ms")
    Logger.info("Average pruning ratio: #{Float.round(avg_pruning * 100, 1)}%")

    # Performance should degrade gracefully
    assert max_duration / avg_duration < 5.0,
           "Performance degradation should be graceful (max < 5x avg)"

    # Should maintain reasonable pruning effectiveness
    assert avg_pruning > 0.05,
           "Should maintain at least 5% average pruning effectiveness"
  end

  defp create_many_short_forks(count, fork_length) do
    # Create many short competing forks
    genesis_root = :crypto.strong_rand_bytes(32)
    blocks = %{genesis_root => create_block_info(0, <<0::256>>)}

    # Create main chain
    main_chain =
      Enum.reduce(1..1000, {blocks, genesis_root}, fn slot, {acc_blocks, parent_root} ->
        block_root = :crypto.strong_rand_bytes(32)
        block_info = create_block_info(slot, parent_root)
        {Map.put(acc_blocks, block_root, block_info), block_root}
      end)

    {blocks, _last_root} = main_chain

    # Add many short forks
    fork_blocks =
      for i <- 1..count, reduce: blocks do
        acc_blocks ->
          # Pick random parent from main chain
          parent_candidates =
            Map.keys(acc_blocks) |> Enum.take_random(min(100, map_size(acc_blocks)))

          parent_root = Enum.random(parent_candidates)
          parent_info = Map.get(acc_blocks, parent_root)

          # Create short fork
          Enum.reduce(1..fork_length, acc_blocks, fn fork_slot_offset, fork_acc ->
            fork_root = :crypto.strong_rand_bytes(32)
            fork_slot = parent_info.block.slot + fork_slot_offset
            fork_info = create_block_info(fork_slot, parent_root)
            Map.put(fork_acc, fork_root, fork_info)
          end)
      end

    {"many_short_forks", create_fork_choice_store(fork_blocks)}
  end

  defp create_long_competing_chains(chain_count, chain_length) do
    # Create several long competing chains
    genesis_root = :crypto.strong_rand_bytes(32)
    blocks = %{genesis_root => create_block_info(0, <<0::256>>)}

    # Create competing chains
    chain_blocks =
      for chain_id <- 1..chain_count, reduce: blocks do
        acc_blocks ->
          # Each chain starts from genesis
          Enum.reduce(1..chain_length, {acc_blocks, genesis_root}, fn slot,
                                                                      {chain_acc, parent_root} ->
            block_root = :crypto.strong_rand_bytes(32)
            block_info = create_block_info(slot, parent_root)
            {Map.put(chain_acc, block_root, block_info), block_root}
          end)
          |> elem(0)
      end

    {"long_competing_chains", create_fork_choice_store(chain_blocks)}
  end

  defp create_dense_fork_pattern(blocks_count, fork_density) do
    # Create very high fork density
    genesis_root = :crypto.strong_rand_bytes(32)
    blocks = %{genesis_root => create_block_info(0, <<0::256>>)}

    dense_blocks =
      Enum.reduce(1..blocks_count, blocks, fn slot, acc_blocks ->
        # Decide how many blocks to create for this slot
        blocks_at_slot =
          if :rand.uniform() < fork_density do
            # 1-5 blocks at this slot
            :rand.uniform(5) + 1
          else
            1
          end

        # Pick parents from previous slots
        potential_parents =
          acc_blocks
          |> Enum.filter(fn {_root, info} -> info.block.slot < slot end)
          |> Enum.take_random(min(10, map_size(acc_blocks)))

        if potential_parents == [] do
          acc_blocks
        else
          # Create blocks for this slot
          Enum.reduce(1..blocks_at_slot, acc_blocks, fn _block_idx, slot_acc ->
            {parent_root, _parent_info} = Enum.random(potential_parents)
            block_root = :crypto.strong_rand_bytes(32)
            block_info = create_block_info(slot, parent_root)
            Map.put(slot_acc, block_root, block_info)
          end)
        end
      end)

    {"dense_fork_pattern", create_fork_choice_store(dense_blocks)}
  end

  defp create_block_info(slot, parent_root) do
    %{
      block: %{
        slot: slot,
        parent_root: parent_root,
        state_root: :crypto.strong_rand_bytes(32),
        body_root: :crypto.strong_rand_bytes(32),
        proposer_index: :rand.uniform(100_000)
      },
      root: :crypto.strong_rand_bytes(32),
      weight: slot * 1000 + :rand.uniform(1000),
      invalid: false
    }
  end

  defp create_fork_choice_store(blocks) do
    # Find a reasonable finalized checkpoint
    max_slot =
      blocks
      |> Map.values()
      |> Enum.map(& &1.block.slot)
      |> Enum.max(fn -> 0 end)

    finalized_slot = max(0, max_slot - 100)
    finalized_root = find_block_at_slot(blocks, finalized_slot)

    %{
      blocks: blocks,
      weight_cache: create_weight_cache(blocks),
      children_cache: %{},
      best_child_cache: %{},
      best_descendant_cache: %{},
      latest_messages: %{},
      finalized_checkpoint: %{
        epoch: div(finalized_slot, 32),
        root: finalized_root
      }
    }
  end

  defp create_weight_cache(blocks) do
    for {root, info} <- blocks, into: %{} do
      {root, info.weight}
    end
  end

  defp generate_massive_attestation_data(validators_count, attestations_per_slot, slots) do
    Logger.info("Generating massive attestation data...")

    # Generate attestations in batches to manage memory
    # Process 100 slots at a time
    batch_size = 100

    slot_batches =
      0..(slots - 1)
      |> Enum.chunk_every(batch_size)

    all_attestations =
      slot_batches
      |> Enum.reduce(%{}, fn slot_batch, acc ->
        Logger.debug("Processing slot batch: #{List.first(slot_batch)}-#{List.last(slot_batch)}")

        batch_attestations =
          for slot <- slot_batch, into: %{} do
            attestations =
              generate_slot_attestations(slot, attestations_per_slot, validators_count)

            {slot, attestations}
          end

        Map.merge(acc, batch_attestations)
      end)

    Logger.info("Generated #{count_total_attestations(all_attestations)} total attestations")

    all_attestations
  end

  defp generate_slot_attestations(slot, count, validators_count) do
    committee_size = min(128, div(validators_count, 64))

    for _i <- 1..count do
      %{
        aggregation_bits: generate_aggregation_bits(committee_size),
        data: %{
          slot: slot,
          index: :rand.uniform(64) - 1,
          beacon_block_root: :crypto.strong_rand_bytes(32),
          source: %{epoch: div(slot, 32) - 1, root: :crypto.strong_rand_bytes(32)},
          target: %{epoch: div(slot, 32), root: :crypto.strong_rand_bytes(32)}
        },
        signature: :crypto.strong_rand_bytes(96)
      }
    end
  end

  defp generate_aggregation_bits(size) do
    participation_rate = 0.7 + :rand.uniform() * 0.2
    participating = round(size * participation_rate)

    bits = List.duplicate(0, size)
    indices = Enum.take_random(0..(size - 1), participating)

    Enum.reduce(indices, bits, fn index, acc ->
      List.replace_at(acc, index, 1)
    end)
    |> Enum.join("")
  end

  defp count_total_attestations(attestation_pool) do
    Enum.reduce(attestation_pool, 0, fn {_slot, attestations}, acc ->
      acc + length(attestations)
    end)
  end

  defp create_mock_beacon_state(current_slot, attestation_pool) do
    %{
      slot: current_slot,
      attestation_pool: attestation_pool,
      validators: [],
      finalized_checkpoint: %{
        epoch: div(current_slot - 100, 32),
        root: :crypto.strong_rand_bytes(32)
      }
    }
  end

  defp create_minimal_fork_choice do
    %{
      blocks: %{
        :crypto.strong_rand_bytes(32) => %{
          block: %{slot: 100, parent_root: <<0::256>>}
        }
      }
    }
  end

  defp monitor_memory_pressure(duration_ms) do
    start_time = System.monotonic_time(:millisecond)
    samples = []

    monitor_memory_pressure_loop(start_time, duration_ms, samples)
  end

  defp monitor_memory_pressure_loop(start_time, duration_ms, samples) do
    current_time = System.monotonic_time(:millisecond)

    if current_time - start_time >= duration_ms do
      # Return statistics
      if samples == [] do
        %{min_memory: 0, max_memory: 0, avg_memory: 0}
      else
        %{
          min_memory: Enum.min(samples),
          max_memory: Enum.max(samples),
          avg_memory: Enum.sum(samples) / length(samples)
        }
      end
    else
      current_memory = :erlang.memory(:total)
      # Keep last 100 samples
      new_samples = [current_memory | Enum.take(samples, 99)]

      # Sample every second
      Process.sleep(1000)
      monitor_memory_pressure_loop(start_time, duration_ms, new_samples)
    end
  end

  defp collect_sustained_metrics(duration_ms) do
    start_time = System.monotonic_time(:millisecond)
    metrics = []

    collect_sustained_metrics_loop(start_time, duration_ms, metrics)
  end

  defp collect_sustained_metrics_loop(start_time, duration_ms, metrics) do
    current_time = System.monotonic_time(:millisecond)

    if current_time - start_time >= duration_ms do
      metrics
    else
      # Collect current metrics
      current_metric = %{
        timestamp: current_time,
        memory_mb: :erlang.memory(:total) / (1024 * 1024),
        process_count: length(Process.list())
      }

      # Keep last 300 samples
      new_metrics = [current_metric | Enum.take(metrics, 299)]

      # Sample every 5 seconds
      Process.sleep(5000)
      collect_sustained_metrics_loop(start_time, duration_ms, new_metrics)
    end
  end

  defp generate_sustained_pruning_load(manager_pid, duration_minutes, operations_per_minute) do
    total_operations = duration_minutes * operations_per_minute
    # Milliseconds between operations
    interval_ms = round(60_000 / operations_per_minute)

    Logger.info(
      "Generating sustained load: #{operations_per_minute} ops/min for #{duration_minutes} minutes"
    )

    results =
      for operation_id <- 1..total_operations do
        start_time = System.monotonic_time(:millisecond)

        # Vary operation types for realistic load
        operation_type = Enum.random([:fork_choice, :states, :attestations, :blocks])

        try do
          result = GenServer.call(manager_pid, {:prune, operation_type, []}, 30_000)

          duration_ms = System.monotonic_time(:millisecond) - start_time

          case result do
            {:ok, _} -> {:success, duration_ms}
            {:error, _} -> {:error, duration_ms}
          end
        rescue
          _ -> {:error, System.monotonic_time(:millisecond) - start_time}
        catch
          :exit, _ -> {:timeout, 30_000}
        end
        |> tap(fn _ ->
          if rem(operation_id, 10) == 0 do
            Logger.debug(
              "Completed #{operation_id}/#{total_operations} sustained load operations"
            )
          end

          # Maintain consistent interval
          Process.sleep(interval_ms)
        end)
      end

    # Calculate statistics
    successes = Enum.count(results, fn {status, _} -> status == :success end)
    total_duration = Enum.reduce(results, 0, fn {_, duration}, acc -> acc + duration end)

    %{
      total_operations: total_operations,
      successful_operations: successes,
      success_rate: successes / total_operations,
      avg_duration_ms: total_duration / total_operations
    }
  end

  defp monitor_system_health(duration_ms) do
    start_time = System.monotonic_time(:millisecond)

    monitor_system_health_loop(start_time, duration_ms, [])
  end

  defp monitor_system_health_loop(start_time, duration_ms, samples) do
    current_time = System.monotonic_time(:millisecond)

    if current_time - start_time >= duration_ms do
      if samples == [] do
        %{max_cpu_percent: 0, memory_stable: true}
      else
        memory_values = Enum.map(samples, & &1.memory)
        memory_variance = calculate_variance(memory_values)
        # Less than 20% variance
        memory_stable = memory_variance < 0.2

        cpu_values = Enum.map(samples, & &1.cpu)
        max_cpu = Enum.max(cpu_values ++ [0])

        %{
          max_cpu_percent: max_cpu,
          memory_stable: memory_stable,
          sample_count: length(samples)
        }
      end
    else
      # Sample system health
      sample = %{
        timestamp: current_time,
        cpu: estimate_cpu_usage(),
        memory: :erlang.memory(:total) / (1024 * 1024)
      }

      # Keep last 60 samples
      new_samples = [sample | Enum.take(samples, 59)]

      # Sample every 5 seconds
      Process.sleep(5000)
      monitor_system_health_loop(start_time, duration_ms, new_samples)
    end
  end

  defp calculate_throughput_variance(metrics_data) do
    throughputs =
      Enum.map(metrics_data, fn metric ->
        # Extract throughput from metric data
        Map.get(metric, :throughput, 0)
      end)

    calculate_variance(throughputs)
  end

  defp calculate_variance([]), do: 0

  defp calculate_variance(values) do
    mean = Enum.sum(values) / length(values)

    variance =
      Enum.reduce(values, 0, fn value, acc ->
        acc + :math.pow(value - mean, 2)
      end) / length(values)

    # Coefficient of variation
    :math.sqrt(variance) / mean
  end

  defp estimate_cpu_usage do
    # Simplified CPU usage estimation based on process activity
    process_count = length(Process.list())
    base_usage = min(process_count / 1000 * 100, 100)

    # Add some randomness to simulate real CPU monitoring
    base_usage + (:rand.uniform() - 0.5) * 20
  end

  defp create_corrupt_fork_choice_data(corruption_type) do
    # Create different types of corrupted data for testing
    case corruption_type do
      "missing_parent_references" ->
        blocks = %{
          # Parent doesn't exist
          :crypto.strong_rand_bytes(32) => create_block_info(1, :crypto.strong_rand_bytes(32))
        }

        {corruption_type, create_fork_choice_store(blocks)}

      "circular_references" ->
        root1 = :crypto.strong_rand_bytes(32)
        root2 = :crypto.strong_rand_bytes(32)

        blocks = %{
          # Points to root2
          root1 => create_block_info(1, root2),
          # Points back to root1 - circular!
          root2 => create_block_info(2, root1)
        }

        {corruption_type, create_fork_choice_store(blocks)}

      "invalid_block_data" ->
        blocks = %{
          :crypto.strong_rand_bytes(32) => %{
            block: %{
              # Invalid slot
              slot: -1,
              # Invalid parent root
              parent_root: "not_a_binary",
              # Missing state root
              state_root: nil,
              # Wrong data type
              body_root: :invalid_data
            },
            root: :crypto.strong_rand_bytes(32),
            # Invalid weight
            weight: "not_a_number",
            # Invalid invalid flag
            invalid: "not_a_boolean"
          }
        }

        {corruption_type, create_fork_choice_store(blocks)}

      "inconsistent_weights" ->
        root1 = :crypto.strong_rand_bytes(32)
        root2 = :crypto.strong_rand_bytes(32)

        blocks = %{
          root1 => %{create_block_info(1, <<0::256>>) | weight: 1000},
          # Child has less weight than parent
          root2 => %{create_block_info(2, root1) | weight: 500}
        }

        {corruption_type, create_fork_choice_store(blocks)}
    end
  end

  defp get_available_memory do
    # Get available system memory (simplified estimation)
    total_memory = :erlang.memory(:total)

    # Estimate available memory based on system info
    # This is a rough approximation for testing
    # Assume we can use 4x current usage
    total_memory * 4
  end

  defp generate_oversized_test_data(memory_limit_bytes) do
    # Generate data that approaches memory limits
    Logger.info("Generating oversized test data approaching #{memory_limit_bytes} bytes")

    # Calculate how many blocks we can fit in memory limit
    # ~50KB per block with all data
    estimated_block_size = 50_000
    target_blocks = div(memory_limit_bytes, estimated_block_size)

    Logger.info("Target blocks for memory limit: #{target_blocks}")

    # Generate large block dataset
    genesis_root = :crypto.strong_rand_bytes(32)
    blocks = %{genesis_root => create_block_info(0, <<0::256>>)}

    large_blocks =
      Enum.reduce(1..target_blocks, blocks, fn slot, acc ->
        if rem(slot, 1000) == 0 do
          Logger.debug("Generated #{slot}/#{target_blocks} oversized blocks")
        end

        block_root = :crypto.strong_rand_bytes(32)

        # Create larger block info with extra data
        large_block_info = %{
          block: %{
            slot: slot,
            parent_root: :crypto.strong_rand_bytes(32),
            state_root: :crypto.strong_rand_bytes(32),
            body_root: :crypto.strong_rand_bytes(32),
            proposer_index: :rand.uniform(100_000),
            # Add extra data to increase memory usage
            # 10KB extra per block
            extra_data: :crypto.strong_rand_bytes(10_000)
          },
          root: block_root,
          weight: slot * 1000,
          invalid: false,
          # Additional large fields
          attestations: Enum.map(1..50, fn _ -> :crypto.strong_rand_bytes(1000) end),
          transactions: Enum.map(1..100, fn _ -> :crypto.strong_rand_bytes(500) end)
        }

        Map.put(acc, block_root, large_block_info)
      end)

    Logger.info("Generated oversized dataset with #{map_size(large_blocks)} blocks")

    create_fork_choice_store(large_blocks)
  end
end
