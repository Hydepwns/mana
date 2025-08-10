defmodule ExWire.Eth2.ParallelAttestationProcessorSimplifiedTest do
  use ExUnit.Case, async: false

  alias ExWire.Eth2.{
    ParallelAttestationProcessorSimplified,
    BeaconState,
    Attestation
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

    # Create simplified fork choice store
    fork_choice_store = %{
      blocks: %{
        <<1::256>> => %{slot: 98},
        <<2::256>> => %{slot: 99},
        <<3::256>> => %{slot: 100}
      }
    }

    {:ok, processor} =
      ParallelAttestationProcessorSimplified.start_link(
        beacon_state: beacon_state,
        fork_choice_store: fork_choice_store,
        name: :"test_processor_simplified_#{System.unique_integer()}"
      )

    %{
      processor: processor,
      beacon_state: beacon_state,
      fork_choice_store: fork_choice_store
    }
  end

  describe "Flow-based parallel processing" do
    test "processes attestations in parallel using Flow", %{
      processor: processor,
      beacon_state: beacon_state,
      fork_choice_store: fork_choice_store
    } do
      # Create batch of attestations
      attestations = create_test_attestations(beacon_state, 50)

      # Measure processing time
      start_time = System.monotonic_time(:millisecond)

      results =
        ParallelAttestationProcessorSimplified.process_attestations(
          attestations,
          beacon_state,
          fork_choice_store
        )

      elapsed_ms = System.monotonic_time(:millisecond) - start_time

      # Verify results structure
      assert is_map(results)
      assert Map.has_key?(results, :valid)
      assert Map.has_key?(results, :invalid)
      assert Map.has_key?(results, :total)
      assert Map.has_key?(results, :success_rate)

      # Verify processing worked
      assert results.total == 50
      # Should have high success rate
      assert results.success_rate >= 0.8

      # Should be reasonably fast
      # 10 seconds max for 50 attestations
      assert elapsed_ms < 10_000

      throughput = results.total * 1000 / elapsed_ms

      IO.puts("\n=== Flow Parallel Processing Results ===")
      IO.puts("Processed: #{results.total} attestations")
      IO.puts("Valid: #{length(results.valid)}")
      IO.puts("Invalid: #{length(results.invalid)}")
      IO.puts("Success Rate: #{Float.round(results.success_rate * 100, 2)}%")
      IO.puts("Time: #{elapsed_ms}ms")
      IO.puts("Throughput: #{Float.round(throughput, 2)} attestations/sec")
      IO.puts("======================================")

      # Should achieve reasonable throughput
      # At least 100 attestations/sec
      assert throughput > 100
    end

    test "handles different batch sizes efficiently", %{
      processor: processor,
      beacon_state: beacon_state,
      fork_choice_store: fork_choice_store
    } do
      batch_sizes = [10, 50, 100, 200]
      results = []

      results =
        Enum.map(batch_sizes, fn size ->
          attestations = create_test_attestations(beacon_state, size)

          {time_us, result} =
            :timer.tc(fn ->
              ParallelAttestationProcessorSimplified.process_attestations(
                attestations,
                beacon_state,
                fork_choice_store
              )
            end)

          throughput = size * 1_000_000 / time_us

          %{
            batch_size: size,
            time_ms: time_us / 1000,
            throughput: throughput,
            success_rate: result.success_rate
          }
        end)

      IO.puts("\n=== Batch Size Performance ===")
      IO.puts("Size\tTime(ms)\tThroughput\tSuccess%")
      IO.puts("----\t--------\t----------\t--------")

      Enum.each(results, fn r ->
        IO.puts(
          "#{r.batch_size}\t#{Float.round(r.time_ms, 1)}\t\t#{Float.round(r.throughput, 0)}\t\t#{Float.round(r.success_rate * 100, 1)}%"
        )
      end)

      IO.puts("===============================")

      # All batches should complete successfully
      Enum.each(results, fn r ->
        assert r.success_rate > 0.5
        assert r.throughput > 50
      end)
    end

    test "processes individual attestations via batching", %{
      processor: processor,
      beacon_state: beacon_state,
      fork_choice_store: fork_choice_store
    } do
      attestations = create_test_attestations(beacon_state, 10)

      # Send individual attestations
      Enum.each(attestations, fn attestation ->
        ParallelAttestationProcessorSimplified.process_attestation(
          attestation,
          beacon_state,
          fork_choice_store
        )
      end)

      # Wait for batch processing
      Process.sleep(200)

      # Check stats
      stats = ParallelAttestationProcessorSimplified.get_stats()

      assert stats.total_processed >= 10
      assert stats.total_validated > 0
      assert stats.current_throughput > 0
    end

    test "validates attestation data in parallel", %{
      processor: processor,
      beacon_state: beacon_state,
      fork_choice_store: fork_choice_store
    } do
      # Create mix of valid and invalid attestations
      valid_attestations = create_test_attestations(beacon_state, 25)
      invalid_attestations = create_invalid_attestations(beacon_state, 25)

      all_attestations = Enum.shuffle(valid_attestations ++ invalid_attestations)

      results =
        ParallelAttestationProcessorSimplified.process_attestations(
          all_attestations,
          beacon_state,
          fork_choice_store
        )

      assert results.total == 50
      assert length(results.valid) + length(results.invalid) == 50
      # Should catch some invalid ones
      assert length(results.invalid) > 0

      # Check that invalid reasons are properly categorized
      invalid_reasons = Enum.map(results.invalid, fn {reason, _} -> reason end)

      expected_reasons = [
        :future_slot,
        :invalid_target_epoch,
        :invalid_signature,
        :no_participants
      ]

      assert Enum.any?(invalid_reasons, &(&1 in expected_reasons))
    end

    test "scales processing across multiple CPU cores", %{
      processor: processor,
      beacon_state: beacon_state,
      fork_choice_store: fork_choice_store
    } do
      # Create large batch to utilize multiple cores
      attestations = create_test_attestations(beacon_state, 500)

      # Monitor CPU usage by measuring processing time vs core count
      core_count = System.schedulers_online()

      {time_us, results} =
        :timer.tc(fn ->
          ParallelAttestationProcessorSimplified.process_attestations(
            attestations,
            beacon_state,
            fork_choice_store
          )
        end)

      throughput = 500 * 1_000_000 / time_us

      IO.puts("\n=== Multi-Core Scaling Test ===")
      IO.puts("CPU Cores: #{core_count}")
      IO.puts("Attestations: 500")
      IO.puts("Processing Time: #{Float.round(time_us / 1000, 1)}ms")
      IO.puts("Throughput: #{Float.round(throughput, 0)} attestations/sec")

      IO.puts(
        "Throughput per Core: #{Float.round(throughput / core_count, 0)} attestations/sec/core"
      )

      IO.puts("===============================")

      # Should achieve reasonable per-core throughput
      per_core_throughput = throughput / core_count
      # At least 50 per core
      assert per_core_throughput > 50

      # Overall throughput should scale with cores  
      assert throughput > core_count * 50
    end

    test "maintains statistics correctly under load", %{
      processor: processor,
      beacon_state: beacon_state,
      fork_choice_store: fork_choice_store
    } do
      # Process multiple batches
      batches = [
        create_test_attestations(beacon_state, 30),
        create_test_attestations(beacon_state, 40),
        create_test_attestations(beacon_state, 50)
      ]

      initial_stats = ParallelAttestationProcessorSimplified.get_stats()

      Enum.each(batches, fn batch ->
        ParallelAttestationProcessorSimplified.process_attestations(
          batch,
          beacon_state,
          fork_choice_store
        )
      end)

      final_stats = ParallelAttestationProcessorSimplified.get_stats()

      # Stats should accumulate properly
      assert final_stats.total_processed >= initial_stats.total_processed + 120
      assert final_stats.total_validated > initial_stats.total_validated
      assert final_stats.average_batch_time_ms > 0
      assert final_stats.current_throughput > 0

      IO.puts("\n=== Processing Statistics ===")
      IO.puts("Total Processed: #{final_stats.total_processed}")
      IO.puts("Total Validated: #{final_stats.total_validated}")
      IO.puts("Total Rejected: #{final_stats.total_rejected}")
      IO.puts("Avg Batch Time: #{Float.round(final_stats.average_batch_time_ms, 2)}ms")

      IO.puts(
        "Current Throughput: #{Float.round(final_stats.current_throughput, 0)} attestations/sec"
      )

      IO.puts("=============================")
    end
  end

  # Helper Functions

  defp create_test_validators(count) do
    Enum.map(0..(count - 1), fn i ->
      %{
        pubkey: <<i::256, 0::256>>,
        withdrawal_credentials: <<0::256>>,
        effective_balance: 32_000_000_000,
        slashed: false,
        activation_eligibility_epoch: 0,
        activation_epoch: 0,
        exit_epoch: 2 ** 64 - 1,
        withdrawable_epoch: 2 ** 64 - 1
      }
    end)
  end

  defp create_test_attestations(beacon_state, count) do
    Enum.map(1..count, fn i ->
      # Vary slots
      slot = beacon_state.slot - rem(i, 10)
      epoch = div(slot, 32)

      %Attestation{
        aggregation_bits: generate_aggregation_bits(64),
        data: %{
          slot: slot,
          index: rem(i, 4),
          beacon_block_root: Enum.at([<<1::256>>, <<2::256>>, <<3::256>>], rem(i, 3)),
          source: %{epoch: max(0, epoch - 1), root: <<1::256>>},
          target: %{epoch: epoch, root: <<2::256>>}
        },
        signature: :crypto.strong_rand_bytes(96)
      }
    end)
  end

  defp create_invalid_attestations(beacon_state, count) do
    Enum.map(1..count, fn i ->
      cond do
        rem(i, 4) == 0 ->
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
            signature: :crypto.strong_rand_bytes(96)
          }

        rem(i, 4) == 1 ->
          # Invalid target epoch
          slot = beacon_state.slot - 5

          %Attestation{
            aggregation_bits: generate_aggregation_bits(64),
            data: %{
              slot: slot,
              index: 0,
              beacon_block_root: <<1::256>>,
              source: %{epoch: 1, root: <<1::256>>},
              # Wrong epoch
              target: %{epoch: 999, root: <<2::256>>}
            },
            signature: :crypto.strong_rand_bytes(96)
          }

        rem(i, 4) == 2 ->
          # Empty aggregation bits (no participants)
          slot = beacon_state.slot - 1

          %Attestation{
            # No participants
            aggregation_bits: <<0::512>>,
            data: %{
              slot: slot,
              index: 0,
              beacon_block_root: <<1::256>>,
              source: %{epoch: 1, root: <<1::256>>},
              target: %{epoch: div(slot, 32), root: <<2::256>>}
            },
            signature: :crypto.strong_rand_bytes(96)
          }

        true ->
          # Unknown block (not in fork choice)
          slot = beacon_state.slot - 1

          %Attestation{
            aggregation_bits: generate_aggregation_bits(64),
            data: %{
              slot: slot,
              index: 0,
              # Unknown block
              beacon_block_root: <<999::256>>,
              source: %{epoch: 1, root: <<1::256>>},
              target: %{epoch: div(slot, 32), root: <<2::256>>}
            },
            signature: :crypto.strong_rand_bytes(96)
          }
      end
    end)
  end

  defp generate_aggregation_bits(bit_count) do
    byte_count = div(bit_count + 7, 8)
    # Generate with some bits set (not all zero)
    bits = :crypto.strong_rand_bytes(byte_count)

    # Ensure at least first bit is set
    case :binary.at(bits, 0) do
      0 -> <<1, :binary.part(bits, 1, byte_count - 1)::binary>>
      _ -> bits
    end
  end
end
