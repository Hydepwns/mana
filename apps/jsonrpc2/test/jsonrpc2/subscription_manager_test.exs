defmodule JSONRPC2.SubscriptionManagerTest do
  use ExUnit.Case, async: false
  
  alias JSONRPC2.SubscriptionManager
  
  setup do
    # Start SubscriptionManager if not already started
    case Process.whereis(SubscriptionManager) do
      nil ->
        {:ok, pid} = SubscriptionManager.start_link()
        on_exit(fn -> Process.exit(pid, :normal) end)
      _pid ->
        :ok
    end
    
    # Create a mock WebSocket PID
    ws_pid = self()
    
    {:ok, %{ws_pid: ws_pid}}
  end
  
  describe "subscribe/3" do
    test "creates a newHeads subscription", %{ws_pid: ws_pid} do
      assert {:ok, subscription_id} = SubscriptionManager.subscribe("newHeads", %{}, ws_pid)
      assert is_binary(subscription_id)
      assert String.starts_with?(subscription_id, "0x")
    end
    
    test "creates a logs subscription with filter", %{ws_pid: ws_pid} do
      filter = %{
        "address" => "0x1234567890123456789012345678901234567890",
        "topics" => ["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"]
      }
      
      assert {:ok, subscription_id} = SubscriptionManager.subscribe("logs", filter, ws_pid)
      assert is_binary(subscription_id)
    end
    
    test "creates a newPendingTransactions subscription", %{ws_pid: ws_pid} do
      assert {:ok, subscription_id} = SubscriptionManager.subscribe("newPendingTransactions", %{}, ws_pid)
      assert is_binary(subscription_id)
    end
    
    test "creates a syncing subscription", %{ws_pid: ws_pid} do
      assert {:ok, subscription_id} = SubscriptionManager.subscribe("syncing", %{}, ws_pid)
      assert is_binary(subscription_id)
    end
    
    test "rejects invalid subscription type", %{ws_pid: ws_pid} do
      assert {:error, "Invalid subscription type: invalidType"} = 
        SubscriptionManager.subscribe("invalidType", %{}, ws_pid)
    end
    
    test "creates multiple subscriptions for same connection", %{ws_pid: ws_pid} do
      assert {:ok, sub1} = SubscriptionManager.subscribe("newHeads", %{}, ws_pid)
      assert {:ok, sub2} = SubscriptionManager.subscribe("logs", %{}, ws_pid)
      assert {:ok, sub3} = SubscriptionManager.subscribe("syncing", %{}, ws_pid)
      
      assert sub1 != sub2
      assert sub2 != sub3
      assert sub1 != sub3
    end
  end
  
  describe "unsubscribe/2" do
    test "cancels an existing subscription", %{ws_pid: ws_pid} do
      {:ok, subscription_id} = SubscriptionManager.subscribe("newHeads", %{}, ws_pid)
      
      assert {:ok, true} = SubscriptionManager.unsubscribe(subscription_id, ws_pid)
    end
    
    test "returns false for non-existent subscription", %{ws_pid: ws_pid} do
      assert {:ok, false} = SubscriptionManager.unsubscribe("0x0000000000000000", ws_pid)
    end
    
    test "prevents unauthorized unsubscribe", %{ws_pid: ws_pid} do
      {:ok, subscription_id} = SubscriptionManager.subscribe("newHeads", %{}, ws_pid)
      
      # Try to unsubscribe from a different PID
      fake_pid = spawn(fn -> :ok end)
      assert {:error, :unauthorized} = SubscriptionManager.unsubscribe(subscription_id, fake_pid)
      Process.exit(fake_pid, :normal)
    end
  end
  
  describe "notifications" do
    test "sends newHeads notification to subscribers", %{ws_pid: ws_pid} do
      {:ok, subscription_id} = SubscriptionManager.subscribe("newHeads", %{}, ws_pid)
      
      # Create a mock block
      block = %{
        header: %{
          difficulty: 1000,
          extra_data: <<1, 2, 3>>,
          gas_limit: 8_000_000,
          gas_used: 500_000,
          block_hash: <<0::256>>,
          logs_bloom: <<0::2048>>,
          beneficiary: <<0::160>>,
          mix_hash: <<0::256>>,
          nonce: <<0::64>>,
          number: 12345,
          parent_hash: <<0::256>>,
          receipts_root: <<0::256>>,
          ommers_hash: <<0::256>>,
          state_root: <<0::256>>,
          timestamp: 1_600_000_000,
          transactions_root: <<0::256>>
        }
      }
      
      SubscriptionManager.notify_new_block(block)
      
      # Should receive notification
      assert_receive {:send_notification, %{
        jsonrpc: "2.0",
        method: "eth_subscription",
        params: %{
          subscription: ^subscription_id,
          result: %{
            difficulty: _,
            extraData: _,
            gasLimit: _,
            gasUsed: _,
            hash: _,
            logsBloom: _,
            miner: _,
            mixHash: _,
            nonce: _,
            number: _,
            parentHash: _,
            receiptsRoot: _,
            sha3Uncles: _,
            stateRoot: _,
            timestamp: _,
            transactionsRoot: _
          }
        }
      }}, 1000
    end
    
    test "sends logs notification to matching subscribers", %{ws_pid: ws_pid} do
      filter = %{
        "address" => "0x1234567890123456789012345678901234567890"
      }
      
      {:ok, subscription_id} = SubscriptionManager.subscribe("logs", filter, ws_pid)
      
      # Create mock logs
      logs = [
        %{
          address: "0x1234567890123456789012345678901234567890",
          topics: ["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"],
          data: <<1, 2, 3, 4>>,
          block_number: 12345,
          transaction_hash: <<0::256>>,
          transaction_index: 0,
          block_hash: <<0::256>>,
          log_index: 0,
          removed: false
        }
      ]
      
      SubscriptionManager.notify_new_logs(logs)
      
      # Should receive notification
      assert_receive {:send_notification, %{
        jsonrpc: "2.0",
        method: "eth_subscription",
        params: %{
          subscription: ^subscription_id,
          result: logs_result
        }
      }}, 1000
      
      assert is_list(logs_result)
      assert length(logs_result) == 1
    end
    
    test "does not send logs notification for non-matching filter", %{ws_pid: ws_pid} do
      filter = %{
        "address" => "0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
      }
      
      {:ok, _subscription_id} = SubscriptionManager.subscribe("logs", filter, ws_pid)
      
      # Create mock logs with different address
      logs = [
        %{
          address: "0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
          topics: [],
          data: <<>>,
          block_number: 12345,
          transaction_hash: <<0::256>>,
          transaction_index: 0,
          block_hash: <<0::256>>,
          log_index: 0,
          removed: false
        }
      ]
      
      SubscriptionManager.notify_new_logs(logs)
      
      # Should NOT receive notification
      refute_receive {:send_notification, _}, 100
    end
    
    test "sends newPendingTransactions notification", %{ws_pid: ws_pid} do
      {:ok, subscription_id} = SubscriptionManager.subscribe("newPendingTransactions", %{}, ws_pid)
      
      # Create mock transaction
      transaction = %{
        hash: <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32>>
      }
      
      SubscriptionManager.notify_new_pending_transaction(transaction)
      
      # Should receive notification
      assert_receive {:send_notification, %{
        jsonrpc: "2.0",
        method: "eth_subscription",
        params: %{
          subscription: ^subscription_id,
          result: tx_hash
        }
      }}, 1000
      
      assert is_binary(tx_hash)
      assert String.starts_with?(tx_hash, "0x")
    end
    
    test "sends syncing notification on status change", %{ws_pid: ws_pid} do
      {:ok, subscription_id} = SubscriptionManager.subscribe("syncing", %{}, ws_pid)
      
      # Notify with sync status
      sync_status = {100, 0, 1000}
      SubscriptionManager.notify_sync_status(sync_status)
      
      # Should receive notification
      assert_receive {:send_notification, %{
        jsonrpc: "2.0",
        method: "eth_subscription",
        params: %{
          subscription: ^subscription_id,
          result: %{
            startingBlock: _,
            currentBlock: _,
            highestBlock: _
          }
        }
      }}, 1000
      
      # Notify with same status - should not receive duplicate
      SubscriptionManager.notify_sync_status(sync_status)
      refute_receive {:send_notification, _}, 100
      
      # Notify with false (sync complete) - should receive
      SubscriptionManager.notify_sync_status(false)
      
      assert_receive {:send_notification, %{
        jsonrpc: "2.0",
        method: "eth_subscription",
        params: %{
          subscription: ^subscription_id,
          result: false
        }
      }}, 1000
    end
  end
  
  describe "cleanup_subscriptions/1" do
    test "removes all subscriptions for disconnected WebSocket", %{ws_pid: ws_pid} do
      # Create multiple subscriptions
      {:ok, sub1} = SubscriptionManager.subscribe("newHeads", %{}, ws_pid)
      {:ok, sub2} = SubscriptionManager.subscribe("logs", %{}, ws_pid)
      {:ok, sub3} = SubscriptionManager.subscribe("syncing", %{}, ws_pid)
      
      # Cleanup subscriptions
      SubscriptionManager.cleanup_subscriptions(ws_pid)
      
      # Try to unsubscribe - should all return false (not found)
      assert {:ok, false} = SubscriptionManager.unsubscribe(sub1, ws_pid)
      assert {:ok, false} = SubscriptionManager.unsubscribe(sub2, ws_pid)
      assert {:ok, false} = SubscriptionManager.unsubscribe(sub3, ws_pid)
    end
  end
  
  describe "process monitoring" do
    test "automatically cleans up subscriptions when WebSocket process dies" do
      # Spawn a process to act as WebSocket
      ws_pid = spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)
      
      # Create subscriptions
      {:ok, subscription_id} = SubscriptionManager.subscribe("newHeads", %{}, ws_pid)
      
      # Kill the process
      Process.exit(ws_pid, :kill)
      
      # Give time for DOWN message to be processed
      Process.sleep(100)
      
      # Subscription should be cleaned up
      assert {:ok, false} = SubscriptionManager.unsubscribe(subscription_id, ws_pid)
    end
  end
end