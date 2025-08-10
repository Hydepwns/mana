defmodule Blockchain.Transaction.BlobTest do
  use ExUnit.Case, async: false  # Changed to false for KZG setup
  
  alias Blockchain.Transaction.Blob
  alias ExWire.Crypto.KZG
  
  describe "Blob Transaction (EIP-4844)" do
    setup do
      # Sample blob versioned hash (KZG version)
      versioned_hash = <<0x01>> <> :crypto.strong_rand_bytes(31)
      
      blob_tx = %Blob{
        chain_id: 1,
        nonce: 42,
        max_priority_fee_per_gas: 1_000_000_000,
        max_fee_per_gas: 2_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: "hello",
        access_list: [],
        max_fee_per_blob_gas: 10_000_000_000,
        blob_versioned_hashes: [versioned_hash],
        v: 0,
        r: 1,
        s: 2
      }
      
      {:ok, blob_tx: blob_tx, versioned_hash: versioned_hash}
    end
    
    test "serializes blob transaction correctly", %{blob_tx: blob_tx} do
      serialized = Blob.serialize(blob_tx)
      
      assert length(serialized) == 14
      assert Enum.at(serialized, 0) == <<1>>  # chain_id
      assert Enum.at(serialized, 1) == <<42>>  # nonce
      assert Enum.at(serialized, 5) == blob_tx.to  # to address
      assert Enum.at(serialized, 7) == "hello"  # data
    end
    
    test "deserializes blob transaction correctly", %{blob_tx: blob_tx} do
      serialized = Blob.serialize(blob_tx)
      {:ok, deserialized} = Blob.deserialize(serialized)
      
      assert deserialized.chain_id == blob_tx.chain_id
      assert deserialized.nonce == blob_tx.nonce
      assert deserialized.to == blob_tx.to
      assert deserialized.data == blob_tx.data
      assert deserialized.blob_versioned_hashes == blob_tx.blob_versioned_hashes
    end
    
    test "calculates total blob gas correctly", %{blob_tx: blob_tx} do
      # One blob should cost 131_072 gas
      assert Blob.get_total_blob_gas(blob_tx) == 131_072
      
      # Multiple blobs
      multi_blob_tx = %{blob_tx | blob_versioned_hashes: List.duplicate(hd(blob_tx.blob_versioned_hashes), 3)}
      assert Blob.get_total_blob_gas(multi_blob_tx) == 3 * 131_072
    end
    
    test "calculates blob fee correctly", %{blob_tx: blob_tx} do
      base_fee = 1_000
      expected_fee = 131_072 * base_fee
      
      assert Blob.get_blob_fee(blob_tx, base_fee) == expected_fee
    end
    
    test "validates blob transaction - success", %{blob_tx: blob_tx} do
      assert Blob.validate(blob_tx) == :ok
    end
    
    test "validates blob transaction - cannot create contract" do
      blob_tx = %Blob{
        chain_id: 1,
        nonce: 1,
        max_priority_fee_per_gas: 1_000_000_000,
        max_fee_per_gas: 2_000_000_000,
        gas_limit: 21_000,
        to: <<>>,  # Empty to address = contract creation
        value: 0,
        data: "",
        access_list: [],
        max_fee_per_blob_gas: 1_000_000_000,
        blob_versioned_hashes: [<<0x01>> <> :crypto.strong_rand_bytes(31)],
        v: 0,
        r: 1,
        s: 2
      }
      
      assert Blob.validate(blob_tx) == {:error, :blob_transaction_cannot_create_contract}
    end
    
    test "validates blob transaction - must have blobs" do
      blob_tx = %Blob{
        chain_id: 1,
        nonce: 1,
        max_priority_fee_per_gas: 1_000_000_000,
        max_fee_per_gas: 2_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: "",
        access_list: [],
        max_fee_per_blob_gas: 1_000_000_000,
        blob_versioned_hashes: [],  # No blobs
        v: 0,
        r: 1,
        s: 2
      }
      
      assert Blob.validate(blob_tx) == {:error, :blob_transaction_must_have_blobs}
    end
    
    test "validates versioned hash - valid KZG hash", %{versioned_hash: versioned_hash} do
      assert Blob.valid_versioned_hash?(versioned_hash) == true
    end
    
    test "validates versioned hash - invalid version" do
      invalid_hash = <<0x02>> <> :crypto.strong_rand_bytes(31)
      assert Blob.valid_versioned_hash?(invalid_hash) == false
    end
    
    test "creates versioned hash from commitment" do
      # 48-byte KZG commitment
      commitment = :crypto.strong_rand_bytes(48)
      versioned_hash = Blob.create_versioned_hash(commitment)
      
      assert byte_size(versioned_hash) == 32
      assert <<version, _rest::binary-size(31)>> = versioned_hash
      assert version == 0x01
      assert Blob.valid_versioned_hash?(versioned_hash) == true
    end
    
    test "converts to standard transaction", %{blob_tx: blob_tx} do
      std_tx = Blob.to_standard_transaction(blob_tx)
      
      assert std_tx.nonce == blob_tx.nonce
      assert std_tx.gas_limit == blob_tx.gas_limit
      assert std_tx.to == blob_tx.to
      assert std_tx.value == blob_tx.value
      assert std_tx.data == blob_tx.data
      assert std_tx.v == blob_tx.v
      assert std_tx.r == blob_tx.r
      assert std_tx.s == blob_tx.s
    end
    
    test "transaction type is 0x03" do
      assert Blob.transaction_type() == 0x03
    end
    
    test "gas per blob constant" do
      assert Blob.gas_per_blob() == 131_072
    end
  end
  
  describe "Access List Serialization" do
    test "serializes empty access list" do
      blob_tx = %Blob{
        chain_id: 1,
        nonce: 1,
        max_priority_fee_per_gas: 1_000_000_000,
        max_fee_per_gas: 2_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: "",
        access_list: [],
        max_fee_per_blob_gas: 1_000_000_000,
        blob_versioned_hashes: [<<0x01>> <> :crypto.strong_rand_bytes(31)],
        v: 0,
        r: 1,
        s: 2
      }
      
      serialized = Blob.serialize(blob_tx)
      access_list_field = Enum.at(serialized, 8)
      assert access_list_field == []
    end
    
    test "serializes access list with entries" do
      address = <<1::160>>
      storage_keys = [<<1::256>>, <<2::256>>]
      
      blob_tx = %Blob{
        chain_id: 1,
        nonce: 1,
        max_priority_fee_per_gas: 1_000_000_000,
        max_fee_per_gas: 2_000_000_000,
        gas_limit: 21_000,
        to: <<2::160>>,
        value: 0,
        data: "",
        access_list: [{address, storage_keys}],
        max_fee_per_blob_gas: 1_000_000_000,
        blob_versioned_hashes: [<<0x01>> <> :crypto.strong_rand_bytes(31)],
        v: 0,
        r: 1,
        s: 2
      }
      
      serialized = Blob.serialize(blob_tx)
      access_list_field = Enum.at(serialized, 8)
      assert access_list_field == [[address, storage_keys]]
      
      # Test round trip
      {:ok, deserialized} = Blob.deserialize(serialized)
      assert deserialized.access_list == [{address, storage_keys}]
    end
  end

  describe "KZG Integration" do
    setup_all do
      # Initialize KZG trusted setup for testing
      case KZG.init_trusted_setup() do
        :ok -> :ok
        error -> raise "Failed to initialize KZG trusted setup: #{inspect(error)}"
      end
    end

    test "generates KZG commitment and proof for blob data" do
      blob_data = generate_test_blob_data()
      
      assert {:ok, {commitment, proof}} = Blob.generate_blob_commitment_and_proof(blob_data)
      assert byte_size(commitment) == 48
      assert byte_size(proof) == 48
    end

    test "verifies KZG proof for blob data" do
      blob_data = generate_test_blob_data()
      
      {:ok, {commitment, proof}} = Blob.generate_blob_commitment_and_proof(blob_data)
      assert {:ok, true} = Blob.verify_blob_kzg_proof(blob_data, commitment, proof)
    end

    test "rejects invalid KZG proof" do
      blob_data = generate_test_blob_data()
      {:ok, {commitment, _valid_proof}} = Blob.generate_blob_commitment_and_proof(blob_data)
      
      invalid_proof = :crypto.strong_rand_bytes(48)
      assert {:ok, false} = Blob.verify_blob_kzg_proof(blob_data, commitment, invalid_proof)
    end

    test "batch verifies multiple blobs" do
      blob_data1 = generate_test_blob_data()
      blob_data2 = generate_different_test_blob_data()
      
      {:ok, {commitment1, proof1}} = Blob.generate_blob_commitment_and_proof(blob_data1)
      {:ok, {commitment2, proof2}} = Blob.generate_blob_commitment_and_proof(blob_data2)
      
      blob_data_list = [blob_data1, blob_data2]
      commitments = [commitment1, commitment2]
      proofs = [proof1, proof2]
      
      assert {:ok, true} = Blob.verify_blob_kzg_proof_batch(blob_data_list, commitments, proofs)
    end

    test "validates complete blob transaction with KZG" do
      blob_data = generate_test_blob_data()
      {:ok, {commitment, proof}} = Blob.generate_blob_commitment_and_proof(blob_data)
      versioned_hash = Blob.create_versioned_hash(commitment)
      
      blob_tx = %Blob{
        chain_id: 1,
        nonce: 1,
        max_priority_fee_per_gas: 1_000_000_000,
        max_fee_per_gas: 2_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: "",
        access_list: [],
        max_fee_per_blob_gas: 1_000_000_000,
        blob_versioned_hashes: [versioned_hash],
        v: 0,
        r: 1,
        s: 2
      }
      
      blob_data_list = [{blob_data, commitment, proof}]
      assert :ok = Blob.validate_with_kzg(blob_tx, blob_data_list)
    end

    test "validates blob data consistency with versioned hashes" do
      blob_data = generate_test_blob_data()
      {:ok, {commitment, proof}} = Blob.generate_blob_commitment_and_proof(blob_data)
      versioned_hash = Blob.create_versioned_hash(commitment)
      
      blob_tx = %Blob{
        chain_id: 1,
        nonce: 1,
        max_priority_fee_per_gas: 1_000_000_000,
        max_fee_per_gas: 2_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: "",
        access_list: [],
        max_fee_per_blob_gas: 1_000_000_000,
        blob_versioned_hashes: [versioned_hash],
        v: 0,
        r: 1,
        s: 2
      }
      
      blob_data_list = [{blob_data, commitment, proof}]
      assert :ok = Blob.validate_blob_data_consistency(blob_tx, blob_data_list)
    end

    test "rejects mismatched versioned hashes" do
      blob_data = generate_test_blob_data()
      {:ok, {commitment, proof}} = Blob.generate_blob_commitment_and_proof(blob_data)
      
      # Use a different commitment for the versioned hash
      different_commitment = :crypto.strong_rand_bytes(48)
      wrong_versioned_hash = Blob.create_versioned_hash(different_commitment)
      
      blob_tx = %Blob{
        chain_id: 1,
        nonce: 1,
        max_priority_fee_per_gas: 1_000_000_000,
        max_fee_per_gas: 2_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: "",
        access_list: [],
        max_fee_per_blob_gas: 1_000_000_000,
        blob_versioned_hashes: [wrong_versioned_hash],
        v: 0,
        r: 1,
        s: 2
      }
      
      blob_data_list = [{blob_data, commitment, proof}]
      assert {:error, {:versioned_hash_mismatch, 0}} = 
        Blob.validate_blob_data_consistency(blob_tx, blob_data_list)
    end

    test "rejects blob count mismatch" do
      blob_tx = %Blob{
        chain_id: 1,
        nonce: 1,
        max_priority_fee_per_gas: 1_000_000_000,
        max_fee_per_gas: 2_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: "",
        access_list: [],
        max_fee_per_blob_gas: 1_000_000_000,
        blob_versioned_hashes: [:crypto.strong_rand_bytes(32), :crypto.strong_rand_bytes(32)],  # 2 hashes
        v: 0,
        r: 1,
        s: 2
      }
      
      # But only provide 1 blob
      blob_data = generate_test_blob_data()
      {:ok, {commitment, proof}} = Blob.generate_blob_commitment_and_proof(blob_data)
      blob_data_list = [{blob_data, commitment, proof}]  # Only 1 blob
      
      assert {:error, :blob_count_mismatch} = 
        Blob.validate_blob_data_consistency(blob_tx, blob_data_list)
    end

    # Helper functions for test data generation

    defp generate_test_blob_data() do
      # Generate valid blob data (131,072 bytes = 4096 * 32-byte field elements)
      field_elements = for i <- 0..4095 do
        # Ensure each field element is valid (< BLS12-381 modulus)
        base_value = rem(i, 116)  # Keep first byte < 0x74 to ensure < modulus
        rest = for j <- 1..31, do: rem(i + j, 256)
        [base_value | rest] |> :binary.list_to_bin()
      end
      
      :binary.list_to_bin(field_elements)
    end

    defp generate_different_test_blob_data() do
      # Generate a different valid blob for testing
      field_elements = for i <- 0..4095 do
        base_value = rem(i + 1, 116)  # Slightly different pattern
        rest = for j <- 1..31, do: rem(i + j + 42, 256)  # Different offset
        [base_value | rest] |> :binary.list_to_bin()
      end
      
      :binary.list_to_bin(field_elements)
    end
  end
end