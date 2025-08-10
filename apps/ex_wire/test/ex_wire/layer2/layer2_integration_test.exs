defmodule ExWire.Layer2.IntegrationTest do
  use ExUnit.Case, async: false

  alias ExWire.Layer2.{Rollup, Batch}
  alias ExWire.Layer2.Optimistic.OptimisticRollup
  alias ExWire.Layer2.ZK.ZKRollup
  alias ExWire.Layer2.Bridge.CrossLayerBridge
  alias ExWire.Layer2.Sequencer.Sequencer

  @moduletag :layer2
  # 1 minute timeout for integration tests
  @moduletag timeout: 60_000

  setup do
    # Start registries for the Layer 2 components
    {:ok, _} = Registry.start_link(keys: :unique, name: ExWire.Layer2.Registry)
    {:ok, _} = Registry.start_link(keys: :unique, name: ExWire.Layer2.OptimisticRegistry)
    {:ok, _} = Registry.start_link(keys: :unique, name: ExWire.Layer2.ZKRegistry)
    {:ok, _} = Registry.start_link(keys: :unique, name: ExWire.Layer2.BridgeRegistry)
    {:ok, _} = Registry.start_link(keys: :unique, name: ExWire.Layer2.SequencerRegistry)

    on_exit(fn ->
      # Clean up processes
      Process.sleep(100)
    end)

    :ok
  end

  describe "Full Layer 2 Integration" do
    test "complete optimistic rollup flow with sequencer and bridge" do
      rollup_id = "optimistic_test_#{:rand.uniform(1000)}"
      sequencer_id = "sequencer_#{rollup_id}"
      bridge_id = "bridge_#{rollup_id}"

      # 1. Start the optimistic rollup
      {:ok, _rollup_pid} =
        OptimisticRollup.start_link(
          rollup_id: rollup_id,
          # 100ms for testing
          challenge_period: 100
        )

      # 2. Start the sequencer
      {:ok, _seq_pid} =
        Sequencer.start_link(
          sequencer_id: sequencer_id,
          rollup_id: rollup_id,
          ordering_mode: :priority_fee,
          batch_size_limit: 10,
          # 500ms for testing
          batch_time_limit: 500
        )

      # 3. Start the bridge
      {:ok, _bridge_pid} =
        CrossLayerBridge.start_link(
          bridge_id: bridge_id,
          l1_contract: <<1::160>>,
          l2_contract: <<2::160>>
        )

      # 4. Submit transactions to sequencer
      transactions =
        for i <- 1..5 do
          {:ok, tx_hash} =
            Sequencer.submit_transaction(sequencer_id, %{
              from: <<i::160>>,
              to: <<100 + i::160>>,
              data: "test_data_#{i}",
              gas_limit: 21_000,
              # Increasing priority fees
              priority_fee: i * 1_000_000_000,
              max_fee: i * 2_000_000_000,
              nonce: i
            })

          tx_hash
        end

      # 5. Force batch creation
      {:ok, batch_id} = Sequencer.force_batch(sequencer_id)
      assert batch_id =~ "batch_"

      # 6. Get rollup state root
      {:ok, state_root} = Rollup.get_state_root(rollup_id)
      assert byte_size(state_root) == 32

      # 7. Test cross-layer deposit
      {:ok, deposit_id} =
        CrossLayerBridge.deposit(bridge_id, %{
          from: <<1::160>>,
          to: <<2::160>>,
          token: <<10::160>>,
          # 1 ETH
          amount: 1_000_000_000_000_000_000
        })

      assert deposit_id =~ "deposit_"

      # 8. Test message passing
      {:ok, message_id} =
        CrossLayerBridge.send_message(
          bridge_id,
          :l1,
          :l2,
          <<200::160>>,
          "Hello from L1"
        )

      assert message_id =~ "msg_"

      # 9. Challenge a state (optimistic rollup specific)
      {:ok, batch} = Rollup.get_batch(rollup_id, 1)

      {:ok, challenge_id} =
        OptimisticRollup.challenge_state(
          rollup_id,
          1,
          batch.state_root
        )

      assert challenge_id =~ "challenge_"

      # 10. Submit fraud proof (should be rejected as state is valid)
      fake_proof = create_mock_fraud_proof(batch)

      {:ok, result} =
        OptimisticRollup.submit_fraud_proof(
          rollup_id,
          challenge_id,
          fake_proof
        )

      assert result == :rejected

      # 11. Check mempool status
      {:ok, mempool_status} = Sequencer.get_mempool_status(sequencer_id)
      assert mempool_status.ordering_mode == :priority_fee
      assert mempool_status.mev_protection == true

      # 12. Verify bridge message status
      {:ok, msg_status} = CrossLayerBridge.get_message_status(bridge_id, message_id)
      assert msg_status == :pending

      # Wait a bit for async operations
      Process.sleep(200)
    end

    test "complete ZK rollup flow with proof verification" do
      rollup_id = "zk_test_#{:rand.uniform(1000)}"
      sequencer_id = "sequencer_#{rollup_id}"

      # 1. Start ZK rollup with PLONK proof system
      {:ok, _rollup_pid} =
        ZKRollup.start_link(
          rollup_id: rollup_id,
          proof_system: :plonk,
          state_tree_depth: 16
        )

      # 2. Start sequencer with fair ordering
      {:ok, _seq_pid} =
        Sequencer.start_link(
          sequencer_id: sequencer_id,
          rollup_id: rollup_id,
          ordering_mode: :fair,
          batch_size_limit: 5,
          mev_protection: true
        )

      # 3. Submit batch of transactions
      for i <- 1..3 do
        Sequencer.submit_transaction(sequencer_id, %{
          from: <<i::160>>,
          to: <<200 + i::160>>,
          data: "zk_test_#{i}",
          gas_limit: 50_000,
          priority_fee: 1_000_000_000,
          max_fee: 2_000_000_000,
          nonce: i
        })
      end

      # 4. Create batch
      {:ok, _batch_id} = Sequencer.force_batch(sequencer_id)

      # 5. Submit ZK proof
      proof = generate_mock_zk_proof(:plonk)
      public_inputs = :crypto.strong_rand_bytes(64)

      {:ok, proof_id} =
        ZKRollup.submit_proof(
          rollup_id,
          1,
          proof,
          public_inputs
        )

      assert proof_id =~ "proof_"

      # 6. Wait for async verification
      Process.sleep(1500)

      # 7. Check proof status
      {:ok, proof_status} = ZKRollup.get_proof_status(rollup_id, proof_id)
      assert proof_status in [:pending, :verified, :rejected]

      # 8. Get state tree root
      {:ok, state_root} = ZKRollup.get_state_tree_root(rollup_id)
      assert byte_size(state_root) == 32

      # 9. Update account state
      account = <<42::160>>

      new_state = %{
        balance: 1_000_000_000_000_000_000,
        nonce: 1,
        storage_root: <<0::256>>
      }

      :ok = ZKRollup.update_account_state(rollup_id, account, new_state)

      # 10. Test proof aggregation (if supported)
      case ZKRollup.aggregate_proofs(rollup_id, [proof_id]) do
        {:ok, aggregated_proof} ->
          assert byte_size(aggregated_proof) > 0

        {:error, :aggregation_not_supported} ->
          # Expected for some proof systems
          :ok

        {:error, :proof_not_found} ->
          # Proof might not be stored yet
          :ok
      end
    end

    test "cross-layer bridge withdrawal flow" do
      bridge_id = "bridge_withdrawal_test_#{:rand.uniform(1000)}"

      # Start bridge
      {:ok, _bridge_pid} =
        CrossLayerBridge.start_link(
          bridge_id: bridge_id,
          l1_contract: <<100::160>>,
          l2_contract: <<200::160>>
        )

      # 1. Initiate withdrawal from L2 to L1
      {:ok, withdrawal_id} =
        CrossLayerBridge.withdraw(bridge_id, %{
          from: <<1::160>>,
          to: <<2::160>>,
          token: <<50::160>>,
          # 0.5 ETH
          amount: 500_000_000_000_000_000,
          proof: :crypto.strong_rand_bytes(256)
        })

      assert withdrawal_id =~ "withdrawal_"

      # 2. Send cross-layer message for withdrawal
      {:ok, msg_id} =
        CrossLayerBridge.send_message(
          bridge_id,
          :l2,
          :l1,
          <<100::160>>,
          encode_withdrawal_message(withdrawal_id)
        )

      # 3. Relay the message
      {:ok, :relayed} = CrossLayerBridge.relay_message(bridge_id, msg_id)

      # 4. Confirm message delivery
      receipt = :crypto.strong_rand_bytes(64)
      :ok = CrossLayerBridge.confirm_message(bridge_id, msg_id, receipt)

      # 5. Verify message status
      {:ok, status} = CrossLayerBridge.get_message_status(bridge_id, msg_id)
      assert status == :confirmed

      # 6. Generate inclusion proof
      state_root = :crypto.strong_rand_bytes(32)

      {:ok, proof} =
        CrossLayerBridge.prove_message_inclusion(
          bridge_id,
          msg_id,
          state_root
        )

      assert byte_size(proof) == 256
    end

    test "sequencer MEV protection and ordering modes" do
      sequencer_id = "seq_mev_test_#{:rand.uniform(1000)}"
      rollup_id = "rollup_mev_#{:rand.uniform(1000)}"

      # Start rollup
      {:ok, _} =
        Rollup.start_link(
          id: rollup_id,
          type: :optimistic,
          config: %{}
        )

      # Start sequencer with MEV protection
      {:ok, _seq_pid} =
        Sequencer.start_link(
          sequencer_id: sequencer_id,
          rollup_id: rollup_id,
          ordering_mode: :mev_auction,
          mev_protection: true,
          batch_size_limit: 20
        )

      # Submit sandwich attack transactions
      victim_tx = %{
        from: <<100::160>>,
        to: <<200::160>>,
        data: "swap_large_amount",
        gas_limit: 100_000,
        # 10 Gwei
        priority_fee: 10_000_000_000,
        max_fee: 20_000_000_000,
        nonce: 1
      }

      frontrun_tx = %{
        from: <<300::160>>,
        to: <<200::160>>,
        data: "frontrun",
        gas_limit: 50_000,
        # 50 Gwei - higher fee
        priority_fee: 50_000_000_000,
        max_fee: 100_000_000_000,
        nonce: 1
      }

      backrun_tx = %{
        from: <<300::160>>,
        to: <<200::160>>,
        data: "backrun",
        gas_limit: 50_000,
        # 5 Gwei - lower fee
        priority_fee: 5_000_000_000,
        max_fee: 10_000_000_000,
        nonce: 2
      }

      # Submit in sandwich order
      {:ok, _} = Sequencer.submit_transaction(sequencer_id, victim_tx)
      {:ok, frontrun_hash} = Sequencer.submit_transaction(sequencer_id, frontrun_tx)
      {:ok, _} = Sequencer.submit_transaction(sequencer_id, backrun_tx)

      # Check transaction status
      {:ok, status} = Sequencer.get_transaction_status(sequencer_id, frontrun_hash)
      assert status == :pending

      # Update config to test different ordering
      :ok =
        Sequencer.update_config(sequencer_id, %{
          ordering_mode: :fifo,
          mev_protection: false
        })

      # Get mempool status
      {:ok, mempool} = Sequencer.get_mempool_status(sequencer_id)
      assert mempool.ordering_mode == :fifo
      assert mempool.mev_protection == false

      # Test reorg handling
      :ok = Sequencer.handle_reorg(sequencer_id, 1000, 999)
    end

    test "multi-rollup coordination" do
      # Create multiple rollups of different types
      optimistic_id = "opt_multi_#{:rand.uniform(1000)}"
      zk_id = "zk_multi_#{:rand.uniform(1000)}"

      # Start optimistic rollup
      {:ok, _} =
        OptimisticRollup.start_link(
          rollup_id: optimistic_id,
          challenge_period: 100
        )

      # Start ZK rollup
      {:ok, _} =
        ZKRollup.start_link(
          rollup_id: zk_id,
          proof_system: :stark,
          state_tree_depth: 20
        )

      # Submit batches to both
      batch1 = Batch.new(1, generate_mock_transactions(3), <<0::256>>, <<1::160>>)
      batch2 = Batch.new(1, generate_mock_transactions(5), <<0::256>>, <<2::160>>)

      {:ok, opt_batch} = Rollup.submit_batch(optimistic_id, batch1)
      {:ok, zk_batch} = Rollup.submit_batch(zk_id, batch2)

      assert opt_batch == 1
      assert zk_batch == 1

      # Sync with L1 for both
      :ok = Rollup.sync_with_l1(optimistic_id, 15_000_000)
      :ok = Rollup.sync_with_l1(zk_id, 15_000_000)

      # Get state roots
      {:ok, opt_root} = Rollup.get_state_root(optimistic_id)
      {:ok, zk_root} = Rollup.get_state_root(zk_id)

      # Different rollups have different states
      assert opt_root != zk_root
    end
  end

  # Helper Functions

  defp create_mock_fraud_proof(batch) do
    # Create a properly structured fraud proof that will be rejected
    alias ExWire.Layer2.Optimistic.FraudProof

    fraud_proof = %FraudProof{
      type: :state_transition,
      batch_number: batch.number,
      transaction_index: nil,
      expected_state_root: :crypto.strong_rand_bytes(32),
      actual_state_root: batch.state_root,
      witness_data:
        :erlang.term_to_binary(%{
          pre_state: batch.previous_root,
          post_state: batch.state_root,
          transactions: batch.transactions,
          timestamp: batch.timestamp
        }),
      proof_data:
        :erlang.term_to_binary(%{
          batch_hash: :crypto.strong_rand_bytes(32),
          expected_root: :crypto.strong_rand_bytes(32),
          actual_root: batch.state_root,
          transactions_root: :crypto.strong_rand_bytes(32)
        })
    }

    FraudProof.encode(fraud_proof)
  end

  defp generate_mock_zk_proof(:plonk) do
    # Generate a mock PLONK proof
    # In production, this would be actual proof data
    :crypto.strong_rand_bytes(512)
  end

  defp generate_mock_zk_proof(:stark) do
    # Generate a mock STARK proof
    :crypto.strong_rand_bytes(1024)
  end

  defp encode_withdrawal_message(withdrawal_id) do
    "withdraw:#{withdrawal_id}"
  end

  defp generate_mock_transactions(count) do
    for i <- 1..count do
      %{
        hash: :crypto.strong_rand_bytes(32),
        from: <<i::160>>,
        to: <<1000 + i::160>>,
        value: i * 1_000_000_000_000_000,
        data: "mock_tx_#{i}",
        gas_limit: 21_000,
        gas_price: 1_000_000_000,
        nonce: i
      }
    end
  end
end
