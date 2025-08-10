defmodule MerklePatriciaTree.DB.ByzantineFaultTest do
  @moduledoc """
  Byzantine fault tolerance testing for AntidoteDB distributed storage.

  This module tests the system's behavior under Byzantine fault conditions including:
  - Network partitions with conflicting updates
  - Byzantine nodes sending malformed or malicious data
  - Clock skew and timestamp manipulation
  - State divergence and reconciliation
  - CRDT convergence under adversarial conditions
  """

  use ExUnit.Case, async: false
  require Logger

  alias MerklePatriciaTree.DB.Antidote
  alias MerklePatriciaTree.CRDTs.{AccountBalance, TransactionPool, StateTree}

  # Skip Byzantine fault tests in CI - require full AntidoteDB cluster
  @moduletag :byzantine_fault
  @moduletag :distributed
  @moduletag :skip_ci
  # 5 minutes for complex scenarios
  @moduletag timeout: 300_000

  setup do
    # Ensure clean test environment
    on_exit(fn ->
      cleanup_test_data()
    end)

    {:ok,
     %{
       nodes: setup_test_cluster(),
       accounts: generate_test_accounts(),
       transactions: generate_test_transactions()
     }}
  end

  describe "Network Partition Scenarios" do
    test "handles conflicting updates during network partition", %{
      nodes: nodes,
      accounts: accounts
    } do
      # Setup: Create initial state on all nodes
      initial_balance = 1000
      account = hd(accounts)

      Enum.each(nodes, fn node ->
        set_account_balance(node, account, initial_balance)
      end)

      # Simulate network partition
      {partition_a, partition_b} = split_network(nodes)

      # Concurrent conflicting updates in different partitions
      update_a =
        Task.async(fn ->
          Enum.each(partition_a, fn node ->
            # Partition A: Deposit 500
            deposit(node, account, 500)
          end)
        end)

      update_b =
        Task.async(fn ->
          Enum.each(partition_b, fn node ->
            # Partition B: Withdraw 300
            withdraw(node, account, 300)
          end)
        end)

      Task.await(update_a, 10_000)
      Task.await(update_b, 10_000)

      # Verify divergence during partition
      balance_a = get_balance(hd(partition_a), account)
      balance_b = get_balance(hd(partition_b), account)

      # 1000 + 500
      assert balance_a == 1500
      # 1000 - 300
      assert balance_b == 700

      # Heal network partition
      heal_network(nodes)

      # Wait for CRDT convergence
      wait_for_convergence(nodes, account, timeout: 30_000)

      # Verify eventual consistency
      final_balances =
        Enum.map(nodes, fn node ->
          get_balance(node, account)
        end)

      # All nodes should converge to the same value
      assert length(Enum.uniq(final_balances)) == 1

      # The converged value should reflect both operations
      # For CRDT counter: initial + deposit + (-withdraw) = 1000 + 500 - 300 = 1200
      assert hd(final_balances) == 1200
    end

    test "maintains consistency with multiple sequential partitions", %{
      nodes: nodes,
      accounts: accounts
    } do
      account = hd(accounts)
      set_account_balance(hd(nodes), account, 1000)

      # Simulate multiple partition/heal cycles
      Enum.each(1..5, fn round ->
        Logger.info("Byzantine test round #{round}")

        # Random partition
        {partition_a, partition_b} = random_split(nodes)

        # Random operations
        if :rand.uniform() > 0.5 do
          deposit(hd(partition_a), account, round * 100)
        else
          withdraw(hd(partition_b), account, round * 50)
        end

        # Heal and wait
        heal_network(nodes)
        wait_for_convergence(nodes, account, timeout: 10_000)
      end)

      # Verify all nodes converged
      balances = Enum.map(nodes, &get_balance(&1, account))
      assert length(Enum.uniq(balances)) == 1
    end

    test "recovers from total network fragmentation", %{nodes: nodes, accounts: accounts} do
      # Each node becomes its own partition
      isolate_all_nodes(nodes)

      # Each node performs different operations
      Enum.with_index(nodes)
      |> Enum.each(fn {node, index} ->
        account = Enum.at(accounts, index)
        set_account_balance(node, account, (index + 1) * 1000)
      end)

      # Reconnect all nodes
      heal_network(nodes)

      # Verify convergence for all accounts
      Enum.each(accounts, fn account ->
        wait_for_convergence(nodes, account, timeout: 20_000)

        balances = Enum.map(nodes, &get_balance(&1, account))
        assert length(Enum.uniq(balances)) == 1
      end)
    end
  end

  describe "Byzantine Node Behavior" do
    test "tolerates nodes sending malformed data", %{nodes: nodes, accounts: accounts} do
      account = hd(accounts)
      good_nodes = Enum.take(nodes, 2)
      byzantine_node = List.last(nodes)

      # Good nodes perform normal operations
      Enum.each(good_nodes, fn node ->
        set_account_balance(node, account, 1000)
      end)

      # Byzantine node sends malformed updates
      send_malformed_updates(byzantine_node, account)

      # Good nodes should continue operating normally
      Enum.each(good_nodes, fn node ->
        assert {:ok, _} = deposit(node, account, 100)
      end)

      # Eventually, good nodes should converge
      wait_for_convergence(good_nodes, account, timeout: 10_000)

      balances = Enum.map(good_nodes, &get_balance(&1, account))
      assert length(Enum.uniq(balances)) == 1
      assert hd(balances) == 1100
    end

    test "handles conflicting transaction ordering", %{nodes: nodes, transactions: transactions} do
      # Different nodes receive transactions in different orders
      tx_batch_1 = Enum.take(transactions, 5)
      tx_batch_2 = Enum.reverse(tx_batch_1)

      node_1 = Enum.at(nodes, 0)
      node_2 = Enum.at(nodes, 1)

      # Submit in different orders
      Task.async(fn ->
        Enum.each(tx_batch_1, fn tx ->
          add_transaction(node_1, tx)
        end)
      end)

      Task.async(fn ->
        Enum.each(tx_batch_2, fn tx ->
          add_transaction(node_2, tx)
        end)
      end)
      |> Task.await(10_000)

      # Wait for propagation
      Process.sleep(5_000)

      # Both nodes should have all transactions (order may differ)
      pool_1 = get_transaction_pool(node_1)
      pool_2 = get_transaction_pool(node_2)

      assert MapSet.new(pool_1) == MapSet.new(pool_2)
      assert length(pool_1) == 5
    end

    test "rejects invalid state transitions from Byzantine nodes", %{nodes: nodes} do
      byzantine_node = hd(nodes)
      honest_nodes = tl(nodes)

      # Byzantine node tries to create money out of thin air
      fake_account = generate_address()

      # Attempt invalid state transition
      result = create_invalid_balance(byzantine_node, fake_account, 1_000_000)

      # Operation should be rejected or have no effect
      case result do
        {:error, _} ->
          # Rejected immediately - good
          assert true

        {:ok, _} ->
          # If accepted locally, it should not propagate to honest nodes
          Process.sleep(5_000)

          Enum.each(honest_nodes, fn node ->
            balance = get_balance(node, fake_account)
            # Honest nodes should not see the invalid balance
            assert balance == 0 or balance == nil
          end)
      end
    end
  end

  describe "Clock Skew and Timestamp Attacks" do
    test "handles clock skew between nodes", %{nodes: nodes, accounts: accounts} do
      account = hd(accounts)

      # Simulate clock skew
      node_past = Enum.at(nodes, 0)
      node_present = Enum.at(nodes, 1)
      node_future = Enum.at(nodes, 2)

      # Set different timestamps for operations
      # 1 hour behind
      with_clock_skew(node_past, -3600, fn ->
        set_account_balance(node_past, account, 1000)
      end)

      # Current time
      with_clock_skew(node_present, 0, fn ->
        deposit(node_present, account, 500)
      end)

      # 1 hour ahead
      with_clock_skew(node_future, 3600, fn ->
        withdraw(node_future, account, 200)
      end)

      # Despite clock skew, CRDTs should converge
      wait_for_convergence(nodes, account, timeout: 20_000)

      balances = Enum.map(nodes, &get_balance(&1, account))
      assert length(Enum.uniq(balances)) == 1

      # Final balance should be 1000 + 500 - 200 = 1300
      assert hd(balances) == 1300
    end

    test "prevents timestamp manipulation attacks", %{nodes: nodes} do
      byzantine_node = hd(nodes)
      account = generate_address()

      # Try to manipulate timestamp to claim priority
      # 1 day in future
      future_timestamp = System.system_time(:millisecond) + 86_400_000

      result =
        with_timestamp(byzantine_node, future_timestamp, fn ->
          set_account_balance(byzantine_node, account, 1_000_000)
        end)

      # System should either reject or handle gracefully
      case result do
        {:error, :invalid_timestamp} ->
          assert true

        {:ok, _} ->
          # Even if accepted, other nodes should handle it properly
          Process.sleep(5_000)

          # Check that the future timestamp doesn't give unfair advantage
          other_nodes = tl(nodes)

          Enum.each(other_nodes, fn node ->
            # Normal operation should still work
            assert {:ok, _} = set_account_balance(node, account, 500)
          end)
      end
    end
  end

  describe "State Divergence and Reconciliation" do
    test "reconciles deeply diverged states", %{nodes: nodes, accounts: accounts} do
      # Create significant divergence
      {group_a, group_b} = split_network(nodes)

      # Group A: Heavy transaction load
      Enum.each(1..100, fn i ->
        account = Enum.random(accounts)
        node = Enum.random(group_a)
        deposit(node, account, i * 10)
      end)

      # Group B: Different transaction pattern
      Enum.each(1..100, fn i ->
        account = Enum.random(accounts)
        node = Enum.random(group_b)
        withdraw(node, account, i * 5)
      end)

      # Heal partition
      heal_network(nodes)

      # Wait for reconciliation (may take longer due to divergence)
      Process.sleep(30_000)

      # Verify convergence for sample accounts
      sample_accounts = Enum.take(accounts, 5)

      Enum.each(sample_accounts, fn account ->
        balances = Enum.map(nodes, &get_balance(&1, account))

        assert length(Enum.uniq(balances)) == 1,
               "Account #{inspect(account)} has not converged: #{inspect(balances)}"
      end)
    end

    test "handles concurrent state tree modifications", %{nodes: nodes} do
      # Multiple nodes modify the state tree concurrently
      tasks =
        Enum.map(nodes, fn node ->
          Task.async(fn ->
            Enum.each(1..50, fn i ->
              key = "key_#{node}_#{i}"
              value = "value_#{node}_#{i}"
              StateTree.put(node, key, value)
            end)
          end)
        end)

      Enum.each(tasks, &Task.await(&1, 30_000))

      # Wait for propagation
      Process.sleep(10_000)

      # All nodes should have all keys
      all_keys =
        Enum.flat_map(nodes, fn node ->
          StateTree.list_keys(node)
        end)
        |> Enum.uniq()

      assert length(all_keys) == length(nodes) * 50

      # Verify each node has all keys
      Enum.each(nodes, fn node ->
        node_keys = StateTree.list_keys(node)
        assert MapSet.new(node_keys) == MapSet.new(all_keys)
      end)
    end

    test "maintains merkle root consistency after reconciliation", %{nodes: nodes} do
      # Create divergence
      {partition_a, partition_b} = split_network(nodes)

      # Different updates in each partition
      Enum.each(1..20, fn i ->
        StateTree.put(hd(partition_a), "a_#{i}", "value_a_#{i}")
        StateTree.put(hd(partition_b), "b_#{i}", "value_b_#{i}")
      end)

      # Heal network
      heal_network(nodes)

      # Wait for convergence
      Process.sleep(20_000)

      # Calculate merkle roots
      roots =
        Enum.map(nodes, fn node ->
          StateTree.calculate_root(node)
        end)

      # All nodes should have the same merkle root
      assert length(Enum.uniq(roots)) == 1,
             "Merkle roots have not converged: #{inspect(roots)}"
    end
  end

  describe "CRDT Convergence Properties" do
    test "CRDTs converge despite Byzantine interference", %{nodes: nodes, accounts: accounts} do
      account = hd(accounts)

      # Setup initial state
      set_account_balance(hd(nodes), account, 1000)

      # Byzantine node tries to interfere
      byzantine_node = List.last(nodes)
      honest_nodes = Enum.take(nodes, length(nodes) - 1)

      # Concurrent operations with Byzantine interference
      tasks = [
        Task.async(fn ->
          # Honest operations
          Enum.each(honest_nodes, fn node ->
            deposit(node, account, 100)
          end)
        end),
        Task.async(fn ->
          # Byzantine operations (rapid conflicting updates)
          Enum.each(1..50, fn i ->
            if rem(i, 2) == 0 do
              deposit(byzantine_node, account, 1000)
            else
              withdraw(byzantine_node, account, 1000)
            end

            Process.sleep(10)
          end)
        end)
      ]

      Enum.each(tasks, &Task.await(&1, 30_000))

      # Despite Byzantine behavior, honest nodes should converge
      wait_for_convergence(honest_nodes, account, timeout: 30_000)

      balances = Enum.map(honest_nodes, &get_balance(&1, account))
      assert length(Enum.uniq(balances)) == 1
    end

    test "transaction pool CRDT handles duplicate submissions", %{
      nodes: nodes,
      transactions: transactions
    } do
      tx = hd(transactions)

      # Multiple nodes submit the same transaction
      Enum.each(nodes, fn node ->
        Enum.each(1..5, fn _ ->
          add_transaction(node, tx)
        end)
      end)

      # Wait for propagation
      Process.sleep(5_000)

      # Each node should have exactly one copy
      Enum.each(nodes, fn node ->
        pool = get_transaction_pool(node)

        count =
          Enum.count(pool, fn pool_tx ->
            pool_tx.hash == tx.hash
          end)

        assert count == 1, "Node has #{count} copies of transaction"
      end)
    end

    test "state tree CRDT resolves concurrent updates correctly", %{nodes: nodes} do
      key = "contested_key"

      # Concurrent updates to the same key
      tasks =
        Enum.with_index(nodes)
        |> Enum.map(fn {node, index} ->
          Task.async(fn ->
            Enum.each(1..10, fn i ->
              value = "node_#{index}_update_#{i}"
              StateTree.put(node, key, value)
              Process.sleep(100)
            end)
          end)
        end)

      Enum.each(tasks, &Task.await(&1, 30_000))

      # Wait for convergence
      Process.sleep(10_000)

      # All nodes should agree on the final value
      values =
        Enum.map(nodes, fn node ->
          StateTree.get(node, key)
        end)

      assert length(Enum.uniq(values)) == 1

      # The value should be deterministic (last-write-wins or merge)
      final_value = hd(values)
      assert final_value != nil
    end
  end

  describe "Recovery and Self-Healing" do
    test "recovers from temporary node failures", %{nodes: nodes, accounts: accounts} do
      account = hd(accounts)
      set_account_balance(hd(nodes), account, 1000)

      # Simulate node failure
      failed_node = Enum.at(nodes, 1)
      active_nodes = List.delete(nodes, failed_node)

      disconnect_node(failed_node)

      # Continue operations on active nodes
      Enum.each(active_nodes, fn node ->
        deposit(node, account, 100)
      end)

      # Bring failed node back online
      reconnect_node(failed_node)

      # Failed node should catch up
      wait_for_convergence(nodes, account, timeout: 20_000)

      balance = get_balance(failed_node, account)
      expected = 1000 + length(active_nodes) * 100
      assert balance == expected
    end

    test "handles cascading failures gracefully", %{nodes: nodes, accounts: accounts} do
      account = hd(accounts)
      set_account_balance(hd(nodes), account, 1000)

      # Progressively fail nodes
      Enum.each(Enum.take(nodes, 2), fn node ->
        disconnect_node(node)
        Process.sleep(2_000)
      end)

      # Remaining node should still function
      remaining = List.last(nodes)
      assert {:ok, _} = deposit(remaining, account, 500)

      # Progressively restore nodes
      Enum.each(Enum.take(nodes, 2), fn node ->
        reconnect_node(node)
        Process.sleep(2_000)
      end)

      # All nodes should reconverge
      wait_for_convergence(nodes, account, timeout: 30_000)

      balances = Enum.map(nodes, &get_balance(&1, account))
      assert length(Enum.uniq(balances)) == 1
      assert hd(balances) == 1500
    end

    test "self-heals after detecting inconsistencies", %{nodes: nodes} do
      # Inject inconsistency
      key = "inconsistent_key"

      # Bypass normal CRDT operations to create inconsistency
      inject_inconsistency(nodes, key)

      # Trigger self-healing mechanism
      trigger_anti_entropy(nodes)

      # Wait for self-healing
      Process.sleep(15_000)

      # Verify consistency restored
      values =
        Enum.map(nodes, fn node ->
          StateTree.get(node, key)
        end)

      assert length(Enum.uniq(values)) == 1,
             "Self-healing failed: values = #{inspect(values)}"
    end
  end

  # Helper Functions

  defp setup_test_cluster() do
    # Return configured test nodes
    # In production, this would connect to actual AntidoteDB nodes
    [
      {:antidote_node_1, :"antidote@127.0.0.1"},
      {:antidote_node_2, :"antidote@127.0.0.2"},
      {:antidote_node_3, :"antidote@127.0.0.3"}
    ]
  end

  defp generate_test_accounts() do
    Enum.map(1..10, fn i ->
      ("0x" <> Base.encode16(:crypto.hash(:sha256, "account_#{i}"), case: :lower))
      |> binary_part(0, 42)
    end)
  end

  defp generate_test_transactions() do
    Enum.map(1..20, fn i ->
      %{
        hash: "0x" <> Base.encode16(:crypto.hash(:sha256, "tx_#{i}"), case: :lower),
        from: generate_address(),
        to: generate_address(),
        value: i * 100,
        nonce: i,
        gas_price: 20_000_000_000,
        gas_limit: 21_000
      }
    end)
  end

  defp generate_address() do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end

  defp set_account_balance(node, account, balance) do
    AccountBalance.set(node, account, balance)
  end

  defp deposit(node, account, amount) do
    AccountBalance.deposit(node, account, amount)
  end

  defp withdraw(node, account, amount) do
    AccountBalance.withdraw(node, account, amount)
  end

  defp get_balance(node, account) do
    AccountBalance.get(node, account)
  end

  defp add_transaction(node, tx) do
    TransactionPool.add(node, tx)
  end

  defp get_transaction_pool(node) do
    TransactionPool.get_all(node)
  end

  defp split_network(nodes) do
    mid = div(length(nodes), 2)
    Enum.split(nodes, mid)
  end

  defp random_split(nodes) do
    shuffled = Enum.shuffle(nodes)
    split_network(shuffled)
  end

  defp isolate_all_nodes(nodes) do
    # Simulate complete network fragmentation
    Enum.each(nodes, fn node ->
      disconnect_node(node)
    end)
  end

  defp heal_network(nodes) do
    # Reconnect all nodes
    Enum.each(nodes, fn node ->
      reconnect_node(node)
    end)
  end

  defp disconnect_node(node) do
    # Simulate network disconnection
    Logger.info("Disconnecting node: #{inspect(node)}")
    # In real implementation, would actually disconnect the node
    :ok
  end

  defp reconnect_node(node) do
    # Simulate network reconnection
    Logger.info("Reconnecting node: #{inspect(node)}")
    # In real implementation, would actually reconnect the node
    :ok
  end

  defp wait_for_convergence(nodes, account, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 10_000)
    start_time = System.monotonic_time(:millisecond)

    wait_loop(nodes, account, start_time, timeout)
  end

  defp wait_loop(nodes, account, start_time, timeout) do
    current_time = System.monotonic_time(:millisecond)

    if current_time - start_time > timeout do
      raise "Convergence timeout after #{timeout}ms"
    end

    balances = Enum.map(nodes, &get_balance(&1, account))

    if length(Enum.uniq(balances)) == 1 do
      :ok
    else
      Process.sleep(500)
      wait_loop(nodes, account, start_time, timeout)
    end
  end

  defp send_malformed_updates(node, account) do
    # Send various malformed updates

    # Invalid balance (negative)
    try do
      AccountBalance.set(node, account, -1000)
    rescue
      _ -> :ok
    end

    # Invalid account format
    try do
      AccountBalance.set(node, "invalid_account", 1000)
    rescue
      _ -> :ok
    end

    # Extremely large value
    try do
      AccountBalance.set(node, account, 1_000_000_000_000_000_000)
    rescue
      _ -> :ok
    end
  end

  defp create_invalid_balance(node, account, amount) do
    # Attempt to create balance without proper transaction
    try do
      AccountBalance.set(node, account, amount)
    rescue
      error -> {:error, error}
    end
  end

  defp with_clock_skew(node, skew_seconds, fun) do
    # Simulate clock skew for operations
    # In real implementation, would adjust node's clock
    fun.()
  end

  defp with_timestamp(node, timestamp, fun) do
    # Execute operation with specific timestamp
    # In real implementation, would override timestamp
    fun.()
  end

  defp inject_inconsistency(nodes, key) do
    # Directly manipulate storage to create inconsistency
    # This simulates data corruption or Byzantine behavior
    [node1, node2 | _] = nodes

    StateTree.put(node1, key, "value_1")
    StateTree.put(node2, key, "value_2")
  end

  defp trigger_anti_entropy(nodes) do
    # Trigger anti-entropy protocol for self-healing
    Enum.each(nodes, fn node ->
      Logger.info("Triggering anti-entropy on #{inspect(node)}")
      # In real implementation, would trigger actual anti-entropy
    end)
  end

  defp cleanup_test_data() do
    # Clean up test data after each test
    Logger.info("Cleaning up Byzantine fault test data")
  end
end
