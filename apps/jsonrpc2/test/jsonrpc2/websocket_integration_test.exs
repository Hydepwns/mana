defmodule JSONRPC2.WebSocketIntegrationTest do
  use ExUnit.Case, async: false
  
  alias JSONRPC2.SpecHandler
  
  @moduledoc """
  Integration tests for WebSocket subscription functionality.
  Tests the complete flow of subscription requests through the handler.
  """
  
  setup do
    # Ensure SubscriptionManager is started
    case Process.whereis(JSONRPC2.SubscriptionManager) do
      nil ->
        {:ok, _pid} = JSONRPC2.SubscriptionManager.start_link()
      _pid ->
        :ok
    end
    
    # Mock WebSocket PID
    ws_context = %{ws_pid: self()}
    
    {:ok, %{ws_context: ws_context}}
  end
  
  describe "eth_subscribe integration" do
    test "subscribes to newHeads through handler", %{ws_context: ws_context} do
      result = SpecHandler.handle_request("eth_subscribe", ["newHeads"], ws_context)
      
      assert is_binary(result)
      assert String.starts_with?(result, "0x")
      assert String.length(result) == 18  # "0x" + 16 hex chars
    end
    
    test "subscribes to logs with filter through handler", %{ws_context: ws_context} do
      filter = %{
        "address" => "0x1234567890123456789012345678901234567890",
        "topics" => ["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"]
      }
      
      result = SpecHandler.handle_request("eth_subscribe", ["logs", filter], ws_context)
      
      assert is_binary(result)
      assert String.starts_with?(result, "0x")
    end
    
    test "rejects subscription without WebSocket context" do
      result = SpecHandler.handle_request("eth_subscribe", ["newHeads"], %{})
      
      assert {:error, "eth_subscribe is only available over WebSocket connections"} = result
    end
  end
  
  describe "eth_unsubscribe integration" do
    test "unsubscribes existing subscription through handler", %{ws_context: ws_context} do
      # First create a subscription
      subscription_id = SpecHandler.handle_request("eth_subscribe", ["newHeads"], ws_context)
      assert is_binary(subscription_id)
      
      # Now unsubscribe
      result = SpecHandler.handle_request("eth_unsubscribe", [subscription_id], ws_context)
      
      assert result == true
    end
    
    test "returns false for non-existent subscription", %{ws_context: ws_context} do
      result = SpecHandler.handle_request("eth_unsubscribe", ["0x0000000000000000"], ws_context)
      
      assert result == false
    end
    
    test "rejects unsubscribe without WebSocket context" do
      result = SpecHandler.handle_request("eth_unsubscribe", ["0x0000000000000000"], %{})
      
      assert {:error, "eth_unsubscribe is only available over WebSocket connections"} = result
    end
  end
  
  describe "JSON-RPC handler integration" do
    test "handles eth_subscribe through JSON-RPC handler with context" do
      json_request = Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "eth_subscribe",
        "params" => ["newHeads"],
        "id" => 1
      })
      
      ws_context = %{ws_pid: self()}
      
      {:reply, response_json} = SpecHandler.handle(json_request, ws_context)
      response = Jason.decode!(response_json)
      
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert is_binary(response["result"])
      assert String.starts_with?(response["result"], "0x")
    end
    
    test "handles eth_unsubscribe through JSON-RPC handler with context" do
      # First subscribe
      ws_context = %{ws_pid: self()}
      
      subscribe_request = Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "eth_subscribe",
        "params" => ["newHeads"],
        "id" => 1
      })
      
      {:reply, subscribe_response} = SpecHandler.handle(subscribe_request, ws_context)
      subscription_id = Jason.decode!(subscribe_response)["result"]
      
      # Now unsubscribe
      unsubscribe_request = Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "eth_unsubscribe",
        "params" => [subscription_id],
        "id" => 2
      })
      
      {:reply, unsubscribe_response} = SpecHandler.handle(unsubscribe_request, ws_context)
      response = Jason.decode!(unsubscribe_response)
      
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 2
      assert response["result"] == true
    end
    
    test "handles batch subscription requests" do
      ws_context = %{ws_pid: self()}
      
      batch_request = Jason.encode!([
        %{
          "jsonrpc" => "2.0",
          "method" => "eth_subscribe",
          "params" => ["newHeads"],
          "id" => 1
        },
        %{
          "jsonrpc" => "2.0",
          "method" => "eth_subscribe",
          "params" => ["logs", %{"address" => "0x1234567890123456789012345678901234567890"}],
          "id" => 2
        },
        %{
          "jsonrpc" => "2.0",
          "method" => "eth_subscribe",
          "params" => ["newPendingTransactions"],
          "id" => 3
        }
      ])
      
      {:reply, response_json} = SpecHandler.handle(batch_request, ws_context)
      responses = Jason.decode!(response_json)
      
      assert is_list(responses)
      assert length(responses) == 3
      
      Enum.each(responses, fn response ->
        assert response["jsonrpc"] == "2.0"
        assert is_binary(response["result"])
        assert String.starts_with?(response["result"], "0x")
      end)
    end
  end
end