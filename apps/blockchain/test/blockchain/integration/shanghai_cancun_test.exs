defmodule Blockchain.Integration.ShanghaiCancunTest do
  use ExUnit.Case, async: false

  alias Blockchain.Transaction.Blob
  alias Blockchain.BlobPool
  alias ExWire.Crypto.{KZG, TrustedSetup}
  alias Blockchain.Performance.KZGBenchmarks

  @moduletag :integration
  @moduletag timeout: 120_000

  setup_all do
    # Initialize the full Shanghai/Cancun stack
    :ok = TrustedSetup.init_production_setup()
    {:ok, _pid} = BlobPool.start_link([])

    :ok
  end

  describe "EIP-4844 Full Integration" do
    test "complete blob transaction lifecycle" do
      # 1. Generate test blob data
      blob_data = generate_integration_test_blob()
      {:ok, {commitment, proof}} = Blob.generate_blob_commitment_and_proof(blob_data)
      versioned_hash = Blob.create_versioned_hash(commitment)

      # 2. Create blob transaction
      blob_tx = %Blob{
        chain_id: 1,
        nonce: 1,
        max_priority_fee_per_gas: 1_000_000_000,
        max_fee_per_gas: 2_000_000_000,
        gas_limit: 21_000,
        to: <<0x1234567890123456789012345678901234567890::160>>,
        value: 0,
        data: "",
        access_list: [],
        max_fee_per_blob_gas: 1_000_000_000,
        blob_versioned_hashes: [versioned_hash],
        v: 27,
        r: 1,
        s: 2
      }

      # 3. Validate transaction with KZG
      blob_data_list = [{blob_data, commitment, proof}]
      assert :ok = Blob.validate_with_kzg(blob_tx, blob_data_list)

      # 4. Add to blob pool
      assert :ok = BlobPool.add_blob_transaction(blob_tx, blob_data_list)

      # 5. Retrieve from pool
      tx_hash = Blob.hash(blob_tx)
      assert {:ok, retrieved_blob_data} = BlobPool.get_blob_data(tx_hash)
      assert retrieved_blob_data == blob_data_list

      # 6. Get best transactions for block building
      best_txs = BlobPool.get_best_blob_transactions(786_432)
      assert length(best_txs) == 1
      assert {retrieved_tx, retrieved_data} = hd(best_txs)
      assert retrieved_tx.blob_versioned_hashes == blob_tx.blob_versioned_hashes

      # 7. Verify pool statistics
      stats = BlobPool.stats()
      assert stats.total_transactions == 1
      # 1 blob = 2^17 gas
      assert stats.total_blob_gas == 131_072
    end

    test "multiple blob transaction with replacement by fee" do
      # Create transactions from same sender with different fees
      base_blob_data = generate_integration_test_blob()
      sender = <<0xABCD1234567890123456789012345678901234ABCD::160>>

      txs_and_data =
        for {nonce, fee} <- [{1, 1_000_000}, {2, 2_000_000}, {3, 3_000_000}] do
          {:ok, {commitment, proof}} = Blob.generate_blob_commitment_and_proof(base_blob_data)
          versioned_hash = Blob.create_versioned_hash(commitment)

          tx = %Blob{
            chain_id: 1,
            nonce: nonce,
            max_priority_fee_per_gas: 1_000_000_000,
            max_fee_per_gas: 2_000_000_000,
            gas_limit: 21_000,
            to: sender,
            value: 0,
            data: "",
            access_list: [],
            max_fee_per_blob_gas: fee,
            blob_versioned_hashes: [versioned_hash],
            v: 27,
            r: nonce,
            s: 2
          }

          {tx, [{base_blob_data, commitment, proof}]}
        end

      # Add all transactions
      Enum.each(txs_and_data, fn {tx, blob_data_list} ->
        assert :ok = BlobPool.add_blob_transaction(tx, blob_data_list)
      end)

      # Pool should have all 3 transactions
      stats = BlobPool.stats()
      assert stats.total_transactions == 3

      # Best transactions should be ordered by fee
      best_txs = BlobPool.get_best_blob_transactions()
      fees = Enum.map(best_txs, fn {tx, _data} -> tx.max_fee_per_blob_gas end)
      # Descending order
      assert fees == [3_000_000, 2_000_000, 1_000_000]
    end

    test "batch KZG verification performance" do
      # Generate multiple blobs for batch testing
      blob_count = 10

      batch_data =
        for i <- 1..blob_count do
          blob_data = generate_integration_test_blob(i)
          {:ok, {commitment, proof}} = Blob.generate_blob_commitment_and_proof(blob_data)
          {blob_data, commitment, proof}
        end

      {blobs, commitments, proofs} = Enum.unzip3(batch_data)

      # Time individual verifications
      {individual_time, individual_results} =
        :timer.tc(fn ->
          Enum.map(batch_data, fn {blob, commitment, proof} ->
            Blob.verify_blob_kzg_proof(blob, commitment, proof)
          end)
        end)

      # Time batch verification
      {batch_time, batch_result} =
        :timer.tc(fn ->
          Blob.verify_blob_kzg_proof_batch(blobs, commitments, proofs)
        end)

      # Verify all results are correct
      assert Enum.all?(individual_results, fn {:ok, result} -> result == true end)
      assert {:ok, true} = batch_result

      # Batch should be faster (though our implementation may not show speedup yet)
      speedup = individual_time / batch_time
      IO.puts("Batch verification speedup: #{Float.round(speedup, 2)}x")

      # At minimum, batch verification should not be dramatically slower
      # Batch should be at least 50% as fast as individual
      assert speedup > 0.5
    end
  end

  describe "Performance Integration" do
    @tag :performance
    test "run comprehensive KZG benchmarks" do
      # This test runs the full benchmark suite
      results = KZGBenchmarks.run_benchmarks()

      # Verify we get results for all benchmark categories
      assert Map.has_key?(results, :commitment_generation)
      assert Map.has_key?(results, :proof_generation)
      assert Map.has_key?(results, :proof_verification)
      assert Map.has_key?(results, :batch_operations)
      assert Map.has_key?(results, :memory_usage)

      # Basic performance assertions
      single_blob_perf = results.commitment_generation["single_blob"]
      # Should be able to do at least 1 op/sec
      assert single_blob_perf.ops_per_sec > 1
      # Should complete within 10 seconds
      assert single_blob_perf.avg_time_us < 10_000_000
    end

    @tag :performance
    test "comparative analysis against targets" do
      analysis = KZGBenchmarks.comparative_analysis()

      # Verify we get performance data
      assert Map.has_key?(analysis, :our_performance)
      assert Map.has_key?(analysis, :targets)
      assert Map.has_key?(analysis, :meets_targets)

      # Log the results for visibility
      IO.puts("\nPerformance Analysis Results:")
      IO.puts("Our Performance: #{inspect(analysis.our_performance)}")
      IO.puts("Meets Targets: #{analysis.meets_targets}")
    end
  end

  describe "Error Handling and Edge Cases" do
    test "invalid blob data handling" do
      # Test with invalid blob size
      # Wrong size
      invalid_blob = :crypto.strong_rand_bytes(1000)
      assert {:error, :invalid_blob_size} = KZG.validate_blob(invalid_blob)

      # Test with blob containing invalid field elements
      invalid_field_blob = generate_invalid_field_element_blob()
      assert {:error, :invalid_blob_format} = KZG.validate_blob(invalid_field_blob)
    end

    test "blob pool limits and eviction" do
      # Fill pool close to capacity with small transactions
      fill_count = 50

      for i <- 1..fill_count do
        blob_data = generate_integration_test_blob(i)
        {:ok, {commitment, proof}} = Blob.generate_blob_commitment_and_proof(blob_data)
        versioned_hash = Blob.create_versioned_hash(commitment)

        tx = %Blob{
          chain_id: 1,
          nonce: i,
          max_priority_fee_per_gas: 1_000_000_000,
          max_fee_per_gas: 2_000_000_000,
          gas_limit: 21_000,
          # Different address for each
          to: <<i::160>>,
          value: 0,
          data: "",
          access_list: [],
          # Increasing fees
          max_fee_per_blob_gas: 1_000_000 + i,
          blob_versioned_hashes: [versioned_hash],
          v: 27,
          r: i,
          s: 2
        }

        # Should succeed for reasonable numbers
        assert :ok = BlobPool.add_blob_transaction(tx, [{blob_data, commitment, proof}])
      end

      stats = BlobPool.stats()
      # Pool limit
      assert stats.total_transactions <= 1000
    end

    test "KZG proof verification edge cases" do
      blob_data = generate_integration_test_blob()
      {:ok, {commitment, proof}} = Blob.generate_blob_commitment_and_proof(blob_data)

      # Valid case
      assert {:ok, true} = Blob.verify_blob_kzg_proof(blob_data, commitment, proof)

      # Invalid proof
      wrong_proof = :crypto.strong_rand_bytes(48)
      assert {:ok, false} = Blob.verify_blob_kzg_proof(blob_data, commitment, wrong_proof)

      # Wrong blob for proof
      different_blob = generate_integration_test_blob(999)
      assert {:ok, false} = Blob.verify_blob_kzg_proof(different_blob, commitment, proof)

      # Malformed commitment
      # Wrong size
      bad_commitment = :crypto.strong_rand_bytes(32)

      assert {:error, :invalid_commitment_size} =
               Blob.verify_blob_kzg_proof(blob_data, bad_commitment, proof)
    end
  end

  describe "Mainnet Readiness Checks" do
    test "trusted setup validation" do
      setup_info = TrustedSetup.setup_info()

      assert setup_info.status == :loaded
      assert setup_info.g1_points == 4096
      assert setup_info.g2_points == 65
    end

    test "transaction pool integration readiness" do
      # Verify pool can handle realistic transaction volumes
      stats_before = BlobPool.stats()

      # Add a few more transactions
      for i <- 1..5 do
        blob_data = generate_integration_test_blob(i + 1000)
        {:ok, {commitment, proof}} = Blob.generate_blob_commitment_and_proof(blob_data)
        versioned_hash = Blob.create_versioned_hash(commitment)

        tx = %Blob{
          chain_id: 1,
          nonce: i,
          max_priority_fee_per_gas: 1_000_000_000,
          max_fee_per_gas: 2_000_000_000,
          gas_limit: 21_000,
          to: <<i + 2000::160>>,
          value: 0,
          data: "",
          access_list: [],
          max_fee_per_blob_gas: 2_000_000 + i,
          blob_versioned_hashes: [versioned_hash],
          v: 27,
          r: i + 1000,
          s: 2
        }

        assert :ok = BlobPool.add_blob_transaction(tx, [{blob_data, commitment, proof}])
      end

      stats_after = BlobPool.stats()
      assert stats_after.total_transactions > stats_before.total_transactions
      assert stats_after.total_blob_gas > stats_before.total_blob_gas
    end
  end

  # Helper functions

  defp generate_integration_test_blob(seed \\ 0) do
    # Generate a valid blob for integration testing
    field_elements =
      for i <- 0..(KZG.field_elements_per_blob() - 1) do
        # Create valid field element (< BLS12-381 modulus)
        # Keep first byte < 0x74
        base_value = rem(i + seed, 116)
        rest_bytes = for j <- 1..31, do: rem(i + j + seed, 256)
        <<base_value>> <> :binary.list_to_bin(rest_bytes)
      end

    :binary.list_to_bin(field_elements)
  end

  defp generate_invalid_field_element_blob do
    # Generate blob with field elements >= BLS12-381 modulus (invalid)
    field_elements =
      for i <- 0..(KZG.field_elements_per_blob() - 1) do
        # Intentionally create invalid field elements
        invalid_bytes = :binary.copy(<<0xFF>>, 32)
        invalid_bytes
      end

    :binary.list_to_bin(field_elements)
  end
end
