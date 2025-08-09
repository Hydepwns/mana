defmodule ExWire.Packet.Capability.Eth.RequestId do
  @moduledoc """
  Support for request IDs in eth/66+ protocol messages.
  
  In eth/66 (EIP-2481), all request-response message pairs have a 64-bit request_id
  prepended to their existing payload. This module handles the encoding/decoding
  of these request IDs.
  """

  @type request_id :: non_neg_integer()

  @doc """
  Generates a new unique request ID.
  Uses timestamp and random component to ensure uniqueness.
  """
  @spec generate() :: request_id()
  def generate() do
    timestamp = System.system_time(:microsecond)
    random = :rand.uniform(0xFFFF)
    # Combine timestamp and random for uniqueness, limit to 64 bits
    rem(timestamp * 0x10000 + random, 0xFFFFFFFFFFFFFFFF)
  end

  @doc """
  Wraps a message payload with a request ID for eth/66+ protocols.
  
  ## Examples
      
      iex> ExWire.Packet.Capability.Eth.RequestId.wrap_message([block_data], 12345)
      [12345, block_data]
  """
  @spec wrap_message(list(), request_id()) :: list()
  def wrap_message(payload, request_id) when is_list(payload) and is_integer(request_id) do
    [request_id | payload]
  end

  @doc """
  Unwraps a message with request ID, returning both the ID and the original payload.
  
  ## Examples
      
      iex> ExWire.Packet.Capability.Eth.RequestId.unwrap_message([12345, block_data])
      {12345, [block_data]}
  """
  @spec unwrap_message(list()) :: {request_id(), list()}
  def unwrap_message([request_id | payload]) when is_integer(request_id) or is_binary(request_id) do
    id = if is_binary(request_id), do: :binary.decode_unsigned(request_id), else: request_id
    {id, payload}
  end

  @doc """
  Checks if a protocol version requires request IDs.
  """
  @spec requires_request_id?(integer()) :: boolean()
  def requires_request_id?(version) when version >= 66, do: true
  def requires_request_id?(_), do: false
end