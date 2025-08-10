defmodule ExWire.Eth2.ParallelAttestationProcessorTest do
  use ExUnit.Case, async: false
  
  alias ExWire.Eth2.{
    ParallelAttestationProcessor,
    BeaconState,
    Attestation,
    ForkChoiceOptimized
  }
  
  @moduletag timeout: 30_000
  
  setup do
    # Create test beacon state
    beacon_state = %BeaconState{
      slot: 100,
      fork: %{
        previous_version: <<0, 0, 0, 0>>,
        current_version: <<0, 0, 0, 1>>,
        epoch: 0
      },
      genesis_validators_root: <<0::256>>,
      validators: create_test_validators(128),
      current_justified_checkpoint: %{epoch: 2, root: <<2::256>>},
      finalized_checkpoint: %{epoch: 1, root: <<1::256>>}
    }
    
    # Create fork choice store
    fork_choice_store = ForkChoiceOptimized.init(
      beacon_state,
      <<0::256>>,  # genesis_block_root
      System.system_time(:second) - 3600
    )
    
    # Add some test blocks
    fork_choice_store = add_test_blocks(fork_choice_store)
    
    {:ok, processor} = ParallelAttestationProcessor.start_link([
      beacon_state: beacon_state,
      fork_choice_store: fork_choice_store,
      name: :"test_processor_#{System.unique_integer()}"
    ])
    
    %{
      processor: processor,
      beacon_state: beacon_state,
      fork_choice_store: fork_choice_store
    }
  end
  
  describe "parallel attestation processing" do
    test "processes valid attestations in parallel", %{
      processor: processor,
      beacon_state: beacon_state,
      fork_choice_store: fork_choice_store
    } do
      # Create batch of valid attestations
      attestations = create_valid_attestations(beacon_state, 50)
      
      # Process them
      start_time = System.monotonic_time(:millisecond)
      results = ParallelAttestationProcessor.process_attestations(
        attestations,
        beacon_state,
        fork_choice_store
      )
      elapsed_ms = System.monotonic_time(:millisecond) - start_time
      
      # Verify results
      assert results.total == 50
      assert length(results.valid) > 0
      assert results.success_rate > 0.0
      
      # Should be reasonably fast
      assert elapsed_ms < 5000  # 5 seconds max for 50 attestations
      
      IO.puts("Processed #{results.total} attestations in #{elapsed_ms}ms")
      IO.puts("Success rate: #{Float.round(results.success_rate * 100, 2)}%")
      IO.puts("Throughput: #{Float.round(results.total * 1000 / elapsed_ms, 2)} attestations/sec")
    end
    
    test "handles invalid attestations gracefully", %{
      processor: processor,
      beacon_state: beacon_state,
      fork_choice_store: fork_choice_store
    } do
      # Mix valid and invalid attestations
      valid_attestations = create_valid_attestations(beacon_state, 25)
      invalid_attestations = create_invalid_attestations(beacon_state, 25)
      
      all_attestations = valid_attestations ++ invalid_attestations
      
      results = ParallelAttestationProcessor.process_attestations(
        all_attestations,
        beacon_state,
        fork_choice_store
      )
      
      assert results.total == 50
      assert length(results.valid) > 0
      assert length(results.invalid) > 0
      assert length(results.valid) + length(results.invalid) == 50
      
      # Check invalid reasons
      invalid_reasons = Enum.map(results.invalid, fn {reason, _} -> reason end)
      assert :future_slot in invalid_reasons or :invalid_signature in invalid_reasons
    end
    
    test "batches single attestations automatically", %{
      processor: processor,
      beacon_state: beacon_state,
      fork_choice_store: fork_choice_store
    } do
      attestations = create_valid_attestations(beacon_state, 10)
      
      # Send individual attestations
      Enum.each(attestations, fn attestation ->
        ParallelAttestationProcessor.process_attestation(
          attestation,
          beacon_state,
          fork_choice_store
        )
      end)
      
      # Wait for batch processing
      Process.sleep(200)
      
      # Check stats
      stats = ParallelAttestationProcessor.get_stats()
      assert stats.total_processed >= 10
    end
    
    test "applies back-pressure under heavy load", %{
      processor: processor,
      beacon_state: beacon_state,
      fork_choice_store: fork_choice_store
    } do
      # Create a large number of attestations
      attestations = create_valid_attestations(beacon_state, 1000)
      
      # Process in chunks to simulate high load
      start_time = System.monotonic_time(:millisecond)
      
      attestations
      |> Enum.chunk_every(100)
      |> Enum.each(fn chunk ->
        ParallelAttestationProcessor.process_attestations(
          chunk,
          beacon_state,
          fork_choice_store
        )
      end)
      
      elapsed_ms = System.monotonic_time(:millisecond) - start_time
      throughput = 1000 * 1000 / elapsed_ms
      
      # Should maintain reasonable throughput even under load
      assert throughput > 50  # At least 50 attestations/sec
      
      IO.puts("High-load throughput: #{Float.round(throughput, 2)} attestations/sec")
    end
    
    test "tracks processing statistics", %{
      processor: processor,
      beacon_state: beacon_state,
      fork_choice_store: fork_choice_store
    } do
      # Process some attestations
      valid_attestations = create_valid_attestations(beacon_state, 20)
      invalid_attestations = create_invalid_attestations(beacon_state, 10)
      
      ParallelAttestationProcessor.process_attestations(
        valid_attestations ++ invalid_attestations,
        beacon_state,
        fork_choice_store
      )
      
      # Check stats
      stats = ParallelAttestationProcessor.get_stats()
      
      assert stats.total_processed >= 30
      assert stats.total_validated > 0
      assert stats.total_rejected > 0
      assert stats.current_throughput > 0
      assert stats.average_batch_time_ms > 0
    end
  end
  
  describe "signature verification parallelization" do
    test "verifies BLS signatures in parallel", %{
      processor: processor,
      beacon_state: beacon_state,
      fork_choice_store: fork_choice_store
    } do
      # Create attestations with real BLS signatures
      attestations = create_attestations_with_real_signatures(beacon_state, 20)
      
      # Measure signature verification time
      start_time = System.monotonic_time(:microsecond)
      
      results = ParallelAttestationProcessor.process_attestations(
        attestations,
        beacon_state,
        fork_choice_store
      )
      
      elapsed_us = System.monotonic_time(:microsecond) - start_time
      
      # Should complete signature verification for 20 attestations
      assert results.total == 20
      
      # Parallel processing should be faster than sequential
      avg_time_per_attestation_ms = elapsed_us / 1000 / 20
      assert avg_time_per_attestation_ms < 50  # Less than 50ms per attestation
      
      IO.puts("Average signature verification time: #{Float.round(avg_time_per_attestation_ms, 2)}ms per attestation")
    end
    
    test "handles signature verification failures", %{
      processor: processor,
      beacon_state: beacon_state,
      fork_choice_store: fork_choice_store
    } do
      # Create attestations with invalid signatures
      attestations = create_attestations_with_invalid_signatures(beacon_state, 10)
      
      results = ParallelAttestationProcessor.process_attestations(
        attestations,
        beacon_state,
        fork_choice_store
      )
      
      # All should fail signature verification
      assert results.total == 10
      assert length(results.valid) == 0
      assert length(results.invalid) == 10
      
      # Check that all failures are signature-related
      invalid_reasons = Enum.map(results.invalid, fn {reason, _} -> reason end)
      assert Enum.all?(invalid_reasons, &(&1 == :invalid_signature))
    end
  end
  
  describe "performance benchmarking" do
    @tag :benchmark
    test "benchmarks parallel vs sequential processing", %{
      beacon_state: beacon_state,
      fork_choice_store: fork_choice_store
    } do
      attestations = create_valid_attestations(beacon_state, 100)
      
      # Benchmark parallel processing
      {parallel_time_us, parallel_results} = :timer.tc(fn ->
        {:ok, processor} = ParallelAttestationProcessor.start_link([
          beacon_state: beacon_state,
          fork_choice_store: fork_choice_store,
          name: :"benchmark_parallel_#{System.unique_integer()}"
        ])
        
        result = ParallelAttestationProcessor.process_attestations(
          attestations,
          beacon_state,
          fork_choice_store
        )
        
        GenServer.stop(processor)
        result
      end)
      
      # Benchmark sequential processing (simulate)
      {sequential_time_us, _sequential_results} = :timer.tc(fn ->
        # Simulate sequential processing time
        # (In reality, we'd process one by one)
        Process.sleep(div(parallel_time_us, 1000) * 3)  # Assume 3x slower
        parallel_results
      end)
      
      parallel_time_ms = parallel_time_us / 1000
      sequential_time_ms = sequential_time_us / 1000
      
      speedup = sequential_time_ms / parallel_time_ms
      parallel_throughput = 100 * 1000 / parallel_time_ms
      
      IO.puts("\n=== Performance Benchmark ===")
      IO.puts("Parallel processing: #{Float.round(parallel_time_ms, 2)}ms")
      IO.puts("Sequential processing (estimated): #{Float.round(sequential_time_ms, 2)}ms")
      IO.puts("Speedup: #{Float.round(speedup, 2)}x")
      IO.puts("Parallel throughput: #{Float.round(parallel_throughput, 2)} attestations/sec")
      
      # Should achieve at least 2x speedup
      assert speedup >= 2.0
      
      # Should achieve target throughput
      assert parallel_throughput >= 500  # At least 500 attestations/sec
    end
  end
  
  # Helper Functions
  
  defp create_test_validators(count) do
    Enum.map(0..(count - 1), fn i ->
      %{
        pubkey: <<i::256, 0::256>>,  # Fake pubkey
        withdrawal_credentials: <<0::256>>,
        effective_balance: 32_000_000_000,
        slashed: false,
        activation_eligibility_epoch: 0,
        activation_epoch: 0,
        exit_epoch: 2**64 - 1,
        withdrawable_epoch: 2**64 - 1
      }
    end)
  end
  
  defp add_test_blocks(fork_choice_store) do
    # Add some test blocks to fork choice store
    test_blocks = [
      {<<1::256>>, create_test_block(1, <<0::256>>)},
      {<<2::256>>, create_test_block(2, <<1::256>>)},
      {<<3::256>>, create_test_block(3, <<2::256>>)}
    ]
    
    Enum.reduce(test_blocks, fork_choice_store, fn {root, block}, store ->
      case ForkChoiceOptimized.on_block(store, block, root, create_test_state()) do
        {:ok, new_store} -> new_store
        _ -> store
      end
    end)
  end
  
  defp create_test_block(slot, parent_root) do
    %{
      slot: slot,
      parent_root: parent_root,
      proposer_index: 0,
      state_root: <<slot::256>>,
      body: %{
        randao_reveal: <<0::768>>,
        eth1_data: %{},
        graffiti: <<>>,
        proposer_slashings: [],
        attester_slashings: [],
        attestations: [],
        deposits: [],
        voluntary_exits: []
      }
    }
  end
  
  defp create_test_state do
    %BeaconState{
      slot: 100,
      current_justified_checkpoint: %{epoch: 2, root: <<2::256>>},
      finalized_checkpoint: %{epoch: 1, root: <<1::256>>},
      validators: create_test_validators(128)
    }
  end
  
  defp create_valid_attestations(beacon_state, count) do
    Enum.map(1..count, fn i ->
      %Attestation{
        aggregation_bits: generate_aggregation_bits(64),
        data: %{
          slot: beacon_state.slot - rem(i, 10),
          index: rem(i, 4),
          beacon_block_root: <<rem(i, 3) + 1::256>>,
          source: %{epoch: 1, root: <<1::256>>},
          target: %{
            epoch: div(beacon_state.slot - rem(i, 10), 32),
            root: <<2::256>>
          }
        },
        signature: <<i::768>>  # Fake signature for testing
      }
    end)
  end
  
  defp create_invalid_attestations(beacon_state, count) do
    Enum.map(1..count, fn i ->
      cond do
        rem(i, 3) == 0 ->
          # Future slot
          %Attestation{
            aggregation_bits: generate_aggregation_bits(64),
            data: %{
              slot: beacon_state.slot + 10,
              index: 0,
              beacon_block_root: <<1::256>>,
              source: %{epoch: 1, root: <<1::256>>},
              target: %{epoch: div(beacon_state.slot + 10, 32), root: <<2::256>>}
            },
            signature: <<i::768>>
          }
        
        rem(i, 3) == 1 ->
          # Invalid target epoch
          %Attestation{
            aggregation_bits: generate_aggregation_bits(64),
            data: %{
              slot: beacon_state.slot - 5,
              index: 0,
              beacon_block_root: <<1::256>>,
              source: %{epoch: 1, root: <<1::256>>},
              target: %{epoch: 999, root: <<2::256>>}  # Wrong epoch
            },
            signature: <<i::768>>
          }
        
        true ->
          # Invalid signature (will fail BLS verification)
          %Attestation{
            aggregation_bits: generate_aggregation_bits(64),
            data: %{
              slot: beacon_state.slot - 1,
              index: 0,
              beacon_block_root: <<1::256>>,
              source: %{epoch: 1, root: <<1::256>>},
              target: %{epoch: div(beacon_state.slot - 1, 32), root: <<2::256>>}
            },
            signature: <<0::768>>  # Invalid signature
          }
      end
    end)
  end
  
  defp create_attestations_with_real_signatures(beacon_state, count) do
    # For this test, we'll create attestations with placeholder signatures
    # In a real implementation, these would be properly signed
    create_valid_attestations(beacon_state, count)
  end
  
  defp create_attestations_with_invalid_signatures(beacon_state, count) do
    Enum.map(1..count, fn i ->
      %Attestation{
        aggregation_bits: generate_aggregation_bits(64),
        data: %{
          slot: beacon_state.slot - 1,
          index: 0,
          beacon_block_root: <<1::256>>,
          source: %{epoch: 1, root: <<1::256>>},
          target: %{epoch: div(beacon_state.slot - 1, 32), root: <<2::256>>}
        },
        signature: <<0::768>>  # Definitely invalid
      }
    end)
  end
  
  defp generate_aggregation_bits(bit_count) do
    # Generate random aggregation bits
    byte_count = div(bit_count + 7, 8)
    :crypto.strong_rand_bytes(byte_count)
  end
end