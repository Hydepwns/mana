defmodule ExWire.Packet.Capability.Eth.V66WrapperTest do
  use ExUnit.Case, async: true

  alias ExWire.Packet.Capability.Eth.V66Wrapper
  alias ExWire.Packet.Capability.Eth.GetBlockHeaders
  alias ExWire.Packet.Capability.Eth.BlockHeaders
  alias ExWire.Packet.Capability.Eth.Status
  alias Block.Header

  describe "wrap_packet/3" do
    test "wraps request messages with request ID for eth/66" do
      packet = %GetBlockHeaders{
        block_identifier: 100,
        max_headers: 10,
        skip: 0,
        reverse: false
      }

      {wrapped, request_id} = V66Wrapper.wrap_packet(packet, 66)

      assert wrapped.request_id != nil
      assert wrapped.packet == packet
      assert request_id != nil
    end

    test "wraps response messages with provided request ID for eth/66" do
      packet = %BlockHeaders{
        headers: []
      }

      {wrapped, _} = V66Wrapper.wrap_packet(packet, 66, 12345)

      assert wrapped.request_id == 12345
      assert wrapped.packet == packet
    end

    test "does not wrap non-request/response messages for eth/66" do
      packet = %Status{
        protocol_version: 66,
        network_id: 1,
        total_difficulty: 100,
        best_hash: <<0::256>>,
        genesis_hash: <<0::256>>
      }

      {result, request_id} = V66Wrapper.wrap_packet(packet, 66)

      assert result == packet
      assert request_id == nil
    end

    test "does not wrap any messages for eth/65 and below" do
      packet = %GetBlockHeaders{
        block_identifier: 100,
        max_headers: 10,
        skip: 0,
        reverse: false
      }

      {result, request_id} = V66Wrapper.wrap_packet(packet, 65)

      assert result == packet
      assert request_id == nil
    end
  end

  describe "serialize/2" do
    test "serializes wrapped packet with request ID for eth/66" do
      packet = %GetBlockHeaders{
        block_identifier: 100,
        max_headers: 10,
        skip: 0,
        reverse: false
      }

      wrapped = %{
        request_id: 12345,
        packet: packet
      }

      result = V66Wrapper.serialize(wrapped, 66)

      assert [12345, 100, 10, 0, 0] == result
    end

    test "serializes non-wrapped packet normally" do
      packet = %Status{
        protocol_version: 66,
        network_id: 1,
        total_difficulty: 100,
        best_hash: <<0::256>>,
        genesis_hash: <<0::256>>
      }

      result = V66Wrapper.serialize(packet, 66)

      # Status packet serialize format
      assert [66, 1, 100, <<0::256>>, <<0::256>>] == result
    end
  end

  describe "deserialize/3" do
    test "deserializes packet with request ID for eth/66" do
      # Request ID 12345 encoded as binary, followed by GetBlockHeaders fields
      rlp_data = [<<0, 0, 48, 57>>, 100, <<10>>, <<0>>, <<0>>]

      result = V66Wrapper.deserialize(rlp_data, GetBlockHeaders, 66)

      assert result.request_id == 12345
      assert result.packet.block_identifier == 100
      assert result.packet.max_headers == 10
      assert result.packet.skip == 0
      assert result.packet.reverse == false
    end

    test "deserializes packet without request ID for eth/65" do
      rlp_data = [100, <<10>>, <<0>>, <<0>>]

      result = V66Wrapper.deserialize(rlp_data, GetBlockHeaders, 65)

      assert result.block_identifier == 100
      assert result.max_headers == 10
      assert result.skip == 0
      assert result.reverse == false
    end
  end

  describe "request tracking" do
    setup do
      V66Wrapper.init_request_tracking()
      :ok
    end

    test "tracks and retrieves request context" do
      request_id = 12345
      context = %{test: "data"}

      :ok = V66Wrapper.track_request(request_id, context)

      assert {:ok, ^context} = V66Wrapper.get_request_context(request_id)
      assert {:error, :not_found} = V66Wrapper.get_request_context(request_id)
    end

    test "cleans up old requests" do
      # Insert an old request
      :ets.insert(:eth_requests, {99999, %{}, System.monotonic_time(:second) - 120})

      # Insert a recent request
      recent_id = 88888
      :ets.insert(:eth_requests, {recent_id, %{}, System.monotonic_time(:second)})

      V66Wrapper.cleanup_old_requests(60)

      # Old request should be gone
      assert :ets.lookup(:eth_requests, 99999) == []

      # Recent request should still exist
      assert [{^recent_id, _, _}] = :ets.lookup(:eth_requests, recent_id)
    end
  end
end
