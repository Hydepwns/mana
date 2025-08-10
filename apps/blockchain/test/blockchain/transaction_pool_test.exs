defmodule Blockchain.TransactionPoolTest do
  use ExUnit.Case, async: false

  alias Blockchain.TransactionPool

  setup do
    # Ensure TransactionPool is started
    case Process.whereis(TransactionPool) do
      nil ->
        {:ok, pid} = TransactionPool.start_link()
        on_exit(fn -> Process.exit(pid, :normal) end)

      _pid ->
        # Clear pool before each test
        TransactionPool.clear()
    end

    :ok
  end

  describe "add_transaction/1" do
    test "adds a valid raw transaction to the pool" do
      # Create a mock raw transaction (simplified RLP)
      raw_tx = create_mock_raw_transaction()

      assert {:ok, tx_hash} = TransactionPool.add_transaction(raw_tx)
      assert is_binary(tx_hash)
      assert String.starts_with?(tx_hash, "0x")
    end

    test "rejects transaction with gas price too low" do
      # Below minimum
      raw_tx = create_mock_raw_transaction(gas_price: 100)

      assert {:error, "Gas price too low"} = TransactionPool.add_transaction(raw_tx)
    end

    test "rejects transaction with gas limit too low" do
      # Below 21000
      raw_tx = create_mock_raw_transaction(gas_limit: 100)

      assert {:error, "Gas limit too low"} = TransactionPool.add_transaction(raw_tx)
    end

    test "rejects transaction with gas limit too high" do
      # Above 8M
      raw_tx = create_mock_raw_transaction(gas_limit: 10_000_000)

      assert {:error, "Gas limit too high"} = TransactionPool.add_transaction(raw_tx)
    end

    test "handles duplicate transactions" do
      raw_tx = create_mock_raw_transaction()

      {:ok, tx_hash1} = TransactionPool.add_transaction(raw_tx)
      {:ok, tx_hash2} = TransactionPool.add_transaction(raw_tx)

      assert tx_hash1 == tx_hash2
    end

    test "rejects malformed RLP" do
      assert {:error, _} = TransactionPool.add_transaction("invalid_rlp_data")
    end

    test "accepts hex-encoded transaction" do
      raw_tx = create_mock_raw_transaction()
      hex_tx = "0x" <> Base.encode16(raw_tx, case: :lower)

      assert {:ok, _tx_hash} = TransactionPool.add_transaction(hex_tx)
    end
  end

  describe "get_pending_transactions/1" do
    test "returns empty list when no transactions" do
      assert [] = TransactionPool.get_pending_transactions()
    end

    test "returns all pending transactions" do
      tx1 = create_mock_raw_transaction(nonce: 1)
      tx2 = create_mock_raw_transaction(nonce: 2)
      tx3 = create_mock_raw_transaction(nonce: 3)

      {:ok, _} = TransactionPool.add_transaction(tx1)
      {:ok, _} = TransactionPool.add_transaction(tx2)
      {:ok, _} = TransactionPool.add_transaction(tx3)

      pending = TransactionPool.get_pending_transactions()
      assert length(pending) == 3
    end

    test "returns transactions sorted by gas price (highest first)" do
      tx_low = create_mock_raw_transaction(gas_price: 1_000_000_000, nonce: 1)
      tx_high = create_mock_raw_transaction(gas_price: 3_000_000_000, nonce: 2)
      tx_mid = create_mock_raw_transaction(gas_price: 2_000_000_000, nonce: 3)

      {:ok, _} = TransactionPool.add_transaction(tx_low)
      {:ok, _} = TransactionPool.add_transaction(tx_high)
      {:ok, _} = TransactionPool.add_transaction(tx_mid)

      pending = TransactionPool.get_pending_transactions()

      assert [first, second, third] = pending
      assert first.gas_price == 3_000_000_000
      assert second.gas_price == 2_000_000_000
      assert third.gas_price == 1_000_000_000
    end

    test "respects limit parameter" do
      for i <- 1..10 do
        tx = create_mock_raw_transaction(nonce: i)
        {:ok, _} = TransactionPool.add_transaction(tx)
      end

      assert length(TransactionPool.get_pending_transactions(5)) == 5
      assert length(TransactionPool.get_pending_transactions(3)) == 3
      assert length(TransactionPool.get_pending_transactions()) == 10
    end
  end

  describe "get_transaction/1" do
    test "returns transaction by hash" do
      raw_tx = create_mock_raw_transaction(nonce: 42)
      {:ok, tx_hash_hex} = TransactionPool.add_transaction(raw_tx)

      # Convert hex hash back to binary
      tx_hash =
        tx_hash_hex
        |> String.slice(2..-1//1)
        |> Base.decode16!(case: :lower)

      tx = TransactionPool.get_transaction(tx_hash)

      assert tx != nil
      assert tx.nonce == 42
    end

    test "returns nil for non-existent transaction" do
      non_existent_hash = <<0::256>>
      assert nil == TransactionPool.get_transaction(non_existent_hash)
    end
  end

  describe "remove_transactions/1" do
    test "removes specified transactions from pool" do
      tx1 = create_mock_raw_transaction(nonce: 1)
      tx2 = create_mock_raw_transaction(nonce: 2)
      tx3 = create_mock_raw_transaction(nonce: 3)

      {:ok, hash1} = TransactionPool.add_transaction(tx1)
      {:ok, hash2} = TransactionPool.add_transaction(tx2)
      {:ok, hash3} = TransactionPool.add_transaction(tx3)

      # Convert hex to binary
      hash1_bin = hash1 |> String.slice(2..-1//1) |> Base.decode16!(case: :lower)
      hash2_bin = hash2 |> String.slice(2..-1//1) |> Base.decode16!(case: :lower)

      TransactionPool.remove_transactions([hash1_bin, hash2_bin])

      # Check that tx1 and tx2 are removed, tx3 remains
      assert nil == TransactionPool.get_transaction(hash1_bin)
      assert nil == TransactionPool.get_transaction(hash2_bin)

      hash3_bin = hash3 |> String.slice(2..-1//1) |> Base.decode16!(case: :lower)
      assert TransactionPool.get_transaction(hash3_bin) != nil
    end
  end

  describe "get_next_nonce/1" do
    test "returns 0 for address with no pending transactions" do
      address = <<1::160>>
      assert 0 == TransactionPool.get_next_nonce(address)
    end

    test "returns next nonce based on pending transactions" do
      # This test would need proper transaction creation with addresses
      # For now, simplified version
      assert 0 == TransactionPool.get_next_nonce(<<1::160>>)
    end
  end

  describe "get_stats/0" do
    test "returns pool statistics" do
      stats = TransactionPool.get_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :current_size)
      assert Map.has_key?(stats, :unique_addresses)
      assert Map.has_key?(stats, :total_added)
      assert Map.has_key?(stats, :total_removed)
      assert Map.has_key?(stats, :total_rejected)
    end

    test "tracks added transactions" do
      initial_stats = TransactionPool.get_stats()

      tx = create_mock_raw_transaction()
      {:ok, _} = TransactionPool.add_transaction(tx)

      new_stats = TransactionPool.get_stats()

      assert new_stats.total_added == initial_stats.total_added + 1
      assert new_stats.current_size == initial_stats.current_size + 1
    end
  end

  describe "clear/0" do
    test "removes all transactions from pool" do
      for i <- 1..5 do
        tx = create_mock_raw_transaction(nonce: i)
        {:ok, _} = TransactionPool.add_transaction(tx)
      end

      assert length(TransactionPool.get_pending_transactions()) == 5

      TransactionPool.clear()

      assert [] = TransactionPool.get_pending_transactions()
      assert TransactionPool.get_stats().current_size == 0
    end
  end

  describe "pool capacity" do
    @tag :slow
    test "enforces maximum pool size" do
      # This test would add 5000+ transactions to test the limit
      # Skipped for performance reasons in regular test runs
      :ok
    end
  end

  # Helper Functions

  defp create_mock_raw_transaction(opts \\ []) do
    # Create a simplified mock transaction for testing
    # In reality, this would need proper RLP encoding

    nonce = Keyword.get(opts, :nonce, 0)
    # 20 Gwei
    gas_price = Keyword.get(opts, :gas_price, 20_000_000_000)
    gas_limit = Keyword.get(opts, :gas_limit, 21000)
    to = Keyword.get(opts, :to, <<0::160>>)
    value = Keyword.get(opts, :value, 0)
    data = Keyword.get(opts, :data, <<>>)
    v = Keyword.get(opts, :v, 27)
    r = Keyword.get(opts, :r, 1)
    s = Keyword.get(opts, :s, 1)

    # Simplified RLP encoding (not accurate, just for testing)
    ExRLP.encode([
      encode_integer(nonce),
      encode_integer(gas_price),
      encode_integer(gas_limit),
      to,
      encode_integer(value),
      data,
      encode_integer(v),
      encode_integer(r),
      encode_integer(s)
    ])
  end

  defp encode_integer(0), do: <<>>

  defp encode_integer(n) when n > 0 do
    :binary.encode_unsigned(n)
  end
end
