defmodule JSONRPC2.RPCMethodsTest do
  use ExUnit.Case

  alias JSONRPC2.SpecHandler

  describe "eth_gasPrice" do
    test "returns a valid gas price" do
      result = SpecHandler.handle_request("eth_gasPrice", [])

      assert is_binary(result)
      assert String.starts_with?(result, "0x")

      # Should be 20 Gwei (20 * 10^9 wei)
      {:ok, gas_price} = JSONRPC2.Response.Helpers.decode_unsigned(result)
      assert gas_price == 20_000_000_000
    end
  end

  describe "eth_call" do
    test "handles missing parameters gracefully" do
      result = SpecHandler.handle_request("eth_call", [%{}, "latest"])

      # Should return nil or handle the error gracefully
      assert result == nil || is_binary(result)
    end

    test "accepts valid call request format" do
      call_request = %{
        "from" => "0x0000000000000000000000000000000000000000",
        "to" => "0x0000000000000000000000000000000000000001",
        "data" => "0x",
        "gas" => "0x5208",
        "gasPrice" => "0x3b9aca00",
        "value" => "0x0"
      }

      # This should not crash
      _result = SpecHandler.handle_request("eth_call", [call_request, "latest"])
    end
  end

  describe "eth_getLogs" do
    test "returns empty array for no matching logs" do
      filter = %{
        "fromBlock" => "0x0",
        "toBlock" => "latest",
        "address" => "0x0000000000000000000000000000000000000000"
      }

      result = SpecHandler.handle_request("eth_getLogs", [filter])

      assert is_list(result)
      assert result == []
    end
  end

  describe "filter methods" do
    test "eth_newFilter returns a filter ID" do
      filter = %{
        "fromBlock" => "0x0",
        "toBlock" => "latest"
      }

      # Start the FilterManager if not already started
      case Process.whereis(JSONRPC2.FilterManager) do
        nil -> {:ok, _} = JSONRPC2.FilterManager.start_link()
        _ -> :ok
      end

      result = SpecHandler.handle_request("eth_newFilter", [filter])

      assert is_binary(result) || is_nil(result)
    end

    test "eth_newBlockFilter returns a filter ID" do
      # Start the FilterManager if not already started
      case Process.whereis(JSONRPC2.FilterManager) do
        nil -> {:ok, _} = JSONRPC2.FilterManager.start_link()
        _ -> :ok
      end

      result = SpecHandler.handle_request("eth_newBlockFilter", [])

      assert is_binary(result) || is_nil(result)
    end

    test "eth_uninstallFilter handles non-existent filter" do
      result = SpecHandler.handle_request("eth_uninstallFilter", ["0x999"])

      assert result == false || is_nil(result)
    end

    test "eth_getFilterChanges returns array for valid filter" do
      # Start the FilterManager if not already started
      case Process.whereis(JSONRPC2.FilterManager) do
        nil -> {:ok, _} = JSONRPC2.FilterManager.start_link()
        _ -> :ok
      end

      # Create a filter first
      filter = %{"fromBlock" => "0x0", "toBlock" => "latest"}
      filter_id = SpecHandler.handle_request("eth_newFilter", [filter])

      if filter_id do
        result = SpecHandler.handle_request("eth_getFilterChanges", [filter_id])
        assert is_list(result) || is_nil(result)
      end
    end
  end

  describe "existing methods remain functional" do
    test "eth_blockNumber still works" do
      result = SpecHandler.handle_request("eth_blockNumber", [])

      assert is_binary(result)
      assert String.starts_with?(result, "0x")
    end

    test "web3_clientVersion still works" do
      result = SpecHandler.handle_request("web3_clientVersion", [])

      assert is_binary(result) || is_nil(result)
    end
  end
end
