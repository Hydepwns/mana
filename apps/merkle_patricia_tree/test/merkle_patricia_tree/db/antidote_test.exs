defmodule MerklePatriciaTree.DB.AntidoteTest do
  use ExUnit.Case, async: false
  alias MerklePatriciaTree.DB
  alias MerklePatriciaTree.DB.Antidote

  describe "init/1" do
    test "init creates an antidote connection" do
      db_name = MerklePatriciaTree.Test.random_atom(20)
      {_, connection} = Antidote.init(db_name)

      # Test that we can perform basic operations
      Antidote.put!(connection, "test_key", "test_value")
      assert Antidote.get(connection, "test_key") == {:ok, "test_value"}
    end

    test "init with different names creates separate connections" do
      db_name1 = MerklePatriciaTree.Test.random_atom(20)
      db_name2 = MerklePatriciaTree.Test.random_atom(20)

      {_, conn1} = Antidote.init(db_name1)
      {_, conn2} = Antidote.init(db_name2)

      # Data should be isolated between connections
      Antidote.put!(conn1, "key", "value1")
      Antidote.put!(conn2, "key", "value2")

      assert Antidote.get(conn1, "key") == {:ok, "value1"}
      assert Antidote.get(conn2, "key") == {:ok, "value2"}
    end
  end

  describe "get/2" do
    test "gets value from db" do
      {_, connection} = Antidote.init(MerklePatriciaTree.Test.random_atom(20))

      Antidote.put!(connection, "key", "value")

      assert Antidote.get(connection, "key") == {:ok, "value"}
      assert Antidote.get(connection, "key2") == :not_found
    end

    test "handles binary keys and values" do
      {_, connection} = Antidote.init(MerklePatriciaTree.Test.random_atom(20))

      binary_key = <<1, 2, 3, 4>>
      binary_value = <<255, 254, 253, 252>>

      Antidote.put!(connection, binary_key, binary_value)
      assert Antidote.get(connection, binary_key) == {:ok, binary_value}
    end

    test "handles large values" do
      {_, connection} = Antidote.init(MerklePatriciaTree.Test.random_atom(20))

      large_value = :crypto.strong_rand_bytes(1024)
      Antidote.put!(connection, "large_key", large_value)
      assert Antidote.get(connection, "large_key") == {:ok, large_value}
    end
  end

  describe "get!/2" do
    test "fails to get value from db" do
      db = {_, connection} = Antidote.init(MerklePatriciaTree.Test.random_atom(20))

      Antidote.put!(connection, "key", "value")
      assert DB.get!(db, "key") == "value"

      assert_raise MerklePatriciaTree.DB.KeyNotFoundError, "cannot find key `key2`", fn ->
        DB.get!(db, "key2")
      end
    end
  end

  describe "put!/3" do
    test "puts value to db" do
      {_, connection} = Antidote.init(MerklePatriciaTree.Test.random_atom(20))

      assert Antidote.put!(connection, "key", "value") == :ok
      assert Antidote.get(connection, "key") == {:ok, "value"}
    end

    test "overwrites existing values" do
      {_, connection} = Antidote.init(MerklePatriciaTree.Test.random_atom(20))

      Antidote.put!(connection, "key", "old_value")
      assert Antidote.get(connection, "key") == {:ok, "old_value"}

      Antidote.put!(connection, "key", "new_value")
      assert Antidote.get(connection, "key") == {:ok, "new_value"}
    end

    test "handles empty values" do
      {_, connection} = Antidote.init(MerklePatriciaTree.Test.random_atom(20))

      assert Antidote.put!(connection, "empty_key", "") == :ok
      assert Antidote.get(connection, "empty_key") == {:ok, ""}
    end
  end

  describe "delete!/2" do
    test "deletes value from db" do
      {_, connection} = Antidote.init(MerklePatriciaTree.Test.random_atom(20))

      Antidote.put!(connection, "key", "value")
      assert Antidote.get(connection, "key") == {:ok, "value"}

      assert Antidote.delete!(connection, "key") == :ok
      assert Antidote.get(connection, "key") == :not_found
    end

    test "deleting non-existent key is ok" do
      {_, connection} = Antidote.init(MerklePatriciaTree.Test.random_atom(20))

      assert Antidote.delete!(connection, "non_existent_key") == :ok
    end
  end

  describe "batch_put!/3" do
    test "puts key value pairs to db" do
      {_, connection} = Antidote.init(MerklePatriciaTree.Test.random_atom(20))

      pairs = [
        {"elixir", "erlang"},
        {"rust", "c++"},
        {"ruby", "crystal"}
      ]

      Enum.each(pairs, fn {key, _value} ->
        assert Antidote.get(connection, key) == :not_found
      end)

      assert Antidote.batch_put!(connection, pairs, 2) == :ok

      Enum.each(pairs, fn {key, value} ->
        assert Antidote.get(connection, key) == {:ok, value}
      end)
    end

    test "handles large batches" do
      {_, connection} = Antidote.init(MerklePatriciaTree.Test.random_atom(20))

      pairs = for i <- 1..100, do: {"key_#{i}", "value_#{i}"}

      assert Antidote.batch_put!(connection, pairs, 10) == :ok

      # Verify all pairs were stored
      Enum.each(pairs, fn {key, value} ->
        assert Antidote.get(connection, key) == {:ok, value}
      end)
    end

    test "handles empty batch" do
      {_, connection} = Antidote.init(MerklePatriciaTree.Test.random_atom(20))

      assert Antidote.batch_put!(connection, [], 10) == :ok
    end
  end

  describe "close/1" do
    test "closes connection" do
      {_, connection} = Antidote.init(MerklePatriciaTree.Test.random_atom(20))

      # Add some data
      Antidote.put!(connection, "key", "value")
      assert Antidote.get(connection, "key") == {:ok, "value"}

      # Close connection
      assert Antidote.close(connection) == :ok

      # Note: In the ETS fallback implementation, data persists
      # In a real AntidoteDB implementation, this would close the connection
    end
  end

  describe "integration with MerklePatriciaTree" do
    test "works with trie operations" do
      {_, connection} = Antidote.init(MerklePatriciaTree.Test.random_atom(20))
      db = {Antidote, connection}

      # Create a simple trie
      trie = MerklePatriciaTree.Trie.new(db)

      # Insert some data
      trie = MerklePatriciaTree.Trie.put_raw_key!(trie, "hello", "world")
      trie = MerklePatriciaTree.Trie.put_raw_key!(trie, "ethereum", "blockchain")

      # Verify data is stored
      assert MerklePatriciaTree.Trie.get_raw_key(trie, "hello") == {:ok, "world"}
      assert MerklePatriciaTree.Trie.get_raw_key(trie, "ethereum") == {:ok, "blockchain"}

      # Verify data persists in the database
      assert Antidote.get(connection, "hello") == {:ok, "world"}
      assert Antidote.get(connection, "ethereum") == {:ok, "blockchain"}
    end
  end

  describe "performance characteristics" do
    test "handles concurrent operations" do
      {_, connection} = Antidote.init(MerklePatriciaTree.Test.random_atom(20))

      # Simulate concurrent operations
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            key = "concurrent_key_#{i}"
            value = "concurrent_value_#{i}"
            Antidote.put!(connection, key, value)
            assert Antidote.get(connection, key) == {:ok, value}
          end)
        end

      Enum.each(tasks, &Task.await/1)
    end
  end
end
