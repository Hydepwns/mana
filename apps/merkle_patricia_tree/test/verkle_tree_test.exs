defmodule VerkleTreeTest do
  use ExUnit.Case, async: true
  
  alias VerkleTree
  alias VerkleTree.{Node, Crypto, Witness, Migration}
  alias MerklePatriciaTree.{Test, Trie}

  describe "VerkleTree basic operations" do
    test "create new verkle tree" do
      db = Test.random_ets_db()
      tree = VerkleTree.new(db)
      
      assert tree.db == db
      assert byte_size(tree.root_commitment) == 32
    end

    test "put and get single value" do
      db = Test.random_ets_db()
      tree = VerkleTree.new(db)
      
      key = "test_key"
      value = "test_value"
      
      updated_tree = VerkleTree.put(tree, key, value)
      assert {:ok, ^value} = VerkleTree.get(updated_tree, key)
    end

    test "get non-existent key returns not_found" do
      db = Test.random_ets_db()
      tree = VerkleTree.new(db)
      
      assert :not_found = VerkleTree.get(tree, "non_existent")
    end

    test "put nil value removes key" do
      db = Test.random_ets_db()
      tree = VerkleTree.new(db)
      
      key = "test_key"
      value = "test_value"
      
      # Put then remove
      tree = VerkleTree.put(tree, key, value)
      assert {:ok, ^value} = VerkleTree.get(tree, key)
      
      tree = VerkleTree.put(tree, key, nil)
      assert :not_found = VerkleTree.get(tree, key)
    end

    test "remove key" do
      db = Test.random_ets_db()
      tree = VerkleTree.new(db)
      
      key = "test_key"
      value = "test_value"
      
      # Put then remove
      tree = VerkleTree.put(tree, key, value)
      tree = VerkleTree.remove(tree, key)
      assert :not_found = VerkleTree.get(tree, key)
    end

    test "multiple keys" do
      db = Test.random_ets_db()
      tree = VerkleTree.new(db)
      
      kvs = [
        {"key1", "value1"},
        {"key2", "value2"},
        {"key3", "value3"}
      ]
      
      # Put all keys
      tree = 
        kvs
        |> Enum.reduce(tree, fn {k, v}, acc -> VerkleTree.put(acc, k, v) end)
      
      # Verify all keys
      Enum.each(kvs, fn {k, v} ->
        assert {:ok, ^v} = VerkleTree.get(tree, k)
      end)
    end

    test "root commitment changes when tree is modified" do
      db = Test.random_ets_db()
      tree = VerkleTree.new(db)
      initial_commitment = tree.root_commitment
      
      updated_tree = VerkleTree.put(tree, "key", "value")
      
      assert updated_tree.root_commitment != initial_commitment
    end
  end

  describe "VerkleTree.Node" do
    test "empty node" do
      node = Node.empty()
      assert node == :empty
    end

    test "leaf node creation" do
      value = "test_value"
      {:leaf, commitment, ^value} = Node.leaf(value)
      assert byte_size(commitment) == 32
    end

    test "internal node creation" do
      children = List.duplicate(<<0::256>>, 256)
      {:internal, ^children} = Node.internal(children)
    end

    test "node encoding and decoding" do
      # Test empty node
      empty_encoded = Node.encode(:empty)
      assert Node.decode(empty_encoded) == :empty
      
      # Test leaf node
      leaf = Node.leaf("test_value")
      leaf_encoded = Node.encode(leaf)
      assert Node.decode(leaf_encoded) == leaf
      
      # Test internal node
      children = List.duplicate(<<0::256>>, 256)
      internal = Node.internal(children)
      internal_encoded = Node.encode(internal)
      assert Node.decode(internal_encoded) == internal
    end

    test "compute commitment" do
      empty_commitment = Node.compute_commitment(:empty)
      assert empty_commitment == <<0::256>>
      
      leaf = Node.leaf("test")
      leaf_commitment = Node.compute_commitment(leaf)
      assert byte_size(leaf_commitment) == 32
      
      children = List.duplicate(<<0::256>>, 256)
      internal = Node.internal(children)
      internal_commitment = Node.compute_commitment(internal)
      assert byte_size(internal_commitment) == 32
    end
  end

  describe "VerkleTree.Crypto" do
    test "commit to value" do
      value = "test_value"
      commitment = Crypto.commit_to_value(value)
      assert byte_size(commitment) == 32
      
      # Same value should produce same commitment
      commitment2 = Crypto.commit_to_value(value)
      assert commitment == commitment2
      
      # Different value should produce different commitment
      commitment3 = Crypto.commit_to_value("different_value")
      assert commitment != commitment3
    end

    test "commit to children" do
      children = List.duplicate(<<0::256>>, 256)
      commitment = Crypto.commit_to_children(children)
      assert byte_size(commitment) == 32
    end

    test "generate and verify proof" do
      path_commitments = [<<1::256>>, <<2::256>>]
      values = ["value1", "value2"]
      root_commitment = <<3::256>>
      
      proof = Crypto.generate_proof(path_commitments, values, root_commitment)
      assert byte_size(proof) == 32
      
      key_value_pairs = [{"key1", "value1"}, {"key2", "value2"}]
      assert Crypto.verify_proof(proof, root_commitment, key_value_pairs)
    end

    test "hash to scalar" do
      data = "test_data"
      scalar = Crypto.hash_to_scalar(data)
      assert byte_size(scalar) == 32
    end

    test "point operations" do
      point1 = Crypto.generator()
      point2 = Crypto.identity()
      scalar = <<1::256>>
      
      # Test scalar multiplication
      result = Crypto.scalar_mul(scalar, point1)
      assert byte_size(result) == 32
      
      # Test point addition
      sum = Crypto.point_add(point1, point2)
      assert byte_size(sum) == 32
    end
  end

  describe "VerkleTree.Witness" do
    test "generate witness" do
      db = Test.random_ets_db()
      tree = VerkleTree.new(db)
      
      # Add some data
      tree = VerkleTree.put(tree, "key1", "value1")
      tree = VerkleTree.put(tree, "key2", "value2")
      
      keys = ["key1", "key2"]
      witness = VerkleTree.generate_witness(tree, keys)
      
      # Keys will be normalized to 32 bytes, so check length instead of exact match
      assert length(witness.keys) == length(keys)
      assert Enum.all?(witness.keys, fn key -> byte_size(key) == 32 end)
      assert length(witness.values) == 2
      assert byte_size(witness.proof) == 32
    end

    test "verify witness" do
      db = Test.random_ets_db()
      tree = VerkleTree.new(db)
      
      tree = VerkleTree.put(tree, "key1", "value1")
      
      witness = VerkleTree.generate_witness(tree, ["key1"])
      key_value_pairs = [{"key1", "value1"}]
      
      assert Witness.verify(witness, tree.root_commitment, key_value_pairs)
    end

    test "witness encoding and decoding" do
      db = Test.random_ets_db()
      tree = VerkleTree.new(db)
      tree = VerkleTree.put(tree, "key1", "value1")
      
      witness = VerkleTree.generate_witness(tree, ["key1"])
      encoded = Witness.encode(witness)
      decoded = Witness.decode(encoded)
      
      assert decoded.keys == witness.keys
      assert decoded.values == witness.values
      assert decoded.proof == witness.proof
    end

    test "witness size" do
      db = Test.random_ets_db()
      tree = VerkleTree.new(db)
      tree = VerkleTree.put(tree, "key1", "value1")
      
      witness = VerkleTree.generate_witness(tree, ["key1"])
      size = Witness.size(witness)
      
      assert size > 0
      # Witnesses should be much smaller than MPT proofs
      assert size < 1000  # Should be around 200 bytes in practice
    end
  end

  describe "VerkleTree.Migration" do
    test "initialize migration" do
      db = Test.random_ets_db()
      mpt = Trie.new(db)
      
      migration = Migration.new(mpt, db)
      
      assert migration.mpt == mpt
      assert migration.verkle.db == db
      assert migration.migration_progress == 0
    end

    test "get with migration - verkle first" do
      db = Test.random_ets_db()
      mpt = Trie.new(db)
      migration = Migration.new(mpt, db)
      
      # Put directly in verkle
      migration = %{migration | verkle: VerkleTree.put(migration.verkle, "key1", "value1")}
      
      {{:ok, value}, _updated_migration} = Migration.get_with_migration(migration, "key1")
      assert value == "value1"
    end

    test "get with migration - MPT fallback and copy" do
      db = Test.random_ets_db()
      mpt = Trie.new(db) |> Trie.update_key("key1", "value1")
      migration = Migration.new(mpt, db)
      
      {{:ok, value}, updated_migration} = Migration.get_with_migration(migration, "key1")
      
      assert value == "value1"
      assert updated_migration.migration_progress == migration.migration_progress + 1
      
      # Verify it was copied to verkle
      assert {:ok, "value1"} = VerkleTree.get(updated_migration.verkle, "key1")
    end

    test "put with migration" do
      db = Test.random_ets_db()
      mpt = Trie.new(db)
      migration = Migration.new(mpt, db)
      
      updated_migration = Migration.put_with_migration(migration, "key1", "value1")
      
      assert {:ok, "value1"} = VerkleTree.get(updated_migration.verkle, "key1")
    end

    test "migration progress calculation" do
      db = Test.random_ets_db()
      mpt = Trie.new(db)
      migration = %{Migration.new(mpt, db) | total_keys: 100, migration_progress: 25}
      
      progress = Migration.migration_progress(migration)
      assert progress == 25.0
    end

    test "migration complete check" do
      db = Test.random_ets_db()
      mpt = Trie.new(db)
      
      incomplete_migration = %{Migration.new(mpt, db) | total_keys: 100, migration_progress: 50}
      refute Migration.migration_complete?(incomplete_migration)
      
      complete_migration = %{Migration.new(mpt, db) | total_keys: 100, migration_progress: 100}
      assert Migration.migration_complete?(complete_migration)
    end

    test "export verkle state" do
      db = Test.random_ets_db()
      mpt = Trie.new(db)
      migration = Migration.new(mpt, db)
      
      {:ok, exported_data} = Migration.export_verkle_state(migration)
      assert is_binary(exported_data)
      
      # Should be able to deserialize
      state_data = :erlang.binary_to_term(exported_data)
      assert Map.has_key?(state_data, :root_commitment)
      assert Map.has_key?(state_data, :migration_progress)
    end
  end

  describe "Integration tests" do
    test "verkle tree vs MPT - same data different structure" do
      db_mpt = Test.random_ets_db()
      db_verkle = Test.random_ets_db() 
      
      mpt = Trie.new(db_mpt)
      verkle = VerkleTree.new(db_verkle)
      
      # Add same data to both
      kvs = [
        {"account1", "balance100"},
        {"account2", "balance200"},
        {"account3", "balance300"}
      ]
      
      mpt = Enum.reduce(kvs, mpt, fn {k, v}, acc -> Trie.update_key(acc, k, v) end)
      verkle = Enum.reduce(kvs, verkle, fn {k, v}, acc -> VerkleTree.put(acc, k, v) end)
      
      # Both should return same values
      Enum.each(kvs, fn {k, v} ->
        assert ^v = Trie.get_key(mpt, k)
        assert {:ok, ^v} = VerkleTree.get(verkle, k)
      end)
      
      # But root hashes should be different (different tree structures)
      assert Trie.root_hash(mpt) != VerkleTree.root_commitment(verkle)
    end

    test "witness size comparison simulation" do
      db = Test.random_ets_db()
      verkle = VerkleTree.new(db)
      
      # Add significant amount of data
      kvs = for i <- 1..100, do: {"key#{i}", "value#{i}"}
      verkle = Enum.reduce(kvs, verkle, fn {k, v}, acc -> VerkleTree.put(acc, k, v) end)
      
      # Generate witness for multiple keys
      keys = Enum.take(kvs, 10) |> Enum.map(fn {k, _} -> k end)
      witness = VerkleTree.generate_witness(verkle, keys)
      
      witness_size = Witness.size(witness)
      
      # Verkle witnesses should be much smaller than MPT proofs
      # MPT proofs are typically ~3KB, verkle should be ~200 bytes
      assert witness_size < 1000  # Much smaller than typical MPT proof
    end

    test "concurrent access simulation" do
      db = Test.random_ets_db()
      verkle = VerkleTree.new(db)
      
      # Simulate concurrent updates
      tasks = for i <- 1..10 do
        Task.async(fn ->
          key = "concurrent_key_#{i}"
          value = "concurrent_value_#{i}"
          VerkleTree.put(verkle, key, value)
        end)
      end
      
      results = Task.await_many(tasks, 5000)
      
      # All tasks should complete successfully
      assert length(results) == 10
      Enum.each(results, fn result ->
        assert %VerkleTree{} = result
      end)
    end

    test "large key space simulation" do
      db = Test.random_ets_db()
      verkle = VerkleTree.new(db)
      
      # Test with various key sizes and formats
      test_keys = [
        "short",
        "medium_length_key_for_testing",
        String.duplicate("very_long_key_", 10),
        <<1, 2, 3, 4, 5>>,  # Binary key
        :crypto.strong_rand_bytes(32),  # Random 32-byte key
        :crypto.strong_rand_bytes(64)   # Random 64-byte key  
      ]
      
      # Put and retrieve all key types
      verkle = Enum.with_index(test_keys)
      |> Enum.reduce(verkle, fn {key, i}, acc -> 
           VerkleTree.put(acc, key, "value_#{i}") 
         end)
      
      # Verify all keys can be retrieved
      Enum.with_index(test_keys)
      |> Enum.each(fn {key, i} ->
           expected_value = "value_#{i}"
           assert {:ok, ^expected_value} = VerkleTree.get(verkle, key)
         end)
    end
  end
end