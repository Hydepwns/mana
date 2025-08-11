defmodule SSZ do
  @moduledoc """
  Simple Serialize (SSZ) encoding/decoding for Ethereum 2.0.
  
  This is a stub implementation for basic compatibility.
  In production, this should be replaced with a proper SSZ library.
  """

  @doc """
  Encode a data structure using SSZ.
  Currently returns a simple binary representation.
  """
  def encode(data) when is_binary(data), do: data
  def encode(data) when is_integer(data), do: <<data::little-32>>
  def encode(data) when is_list(data) do
    # Simple list encoding - prepend length then concatenate items
    encoded_items = Enum.map(data, &encode/1)
    length = byte_size(:binary.list_to_bin(encoded_items))
    <<length::little-32>> <> :binary.list_to_bin(encoded_items)
  end
  def encode(data) when is_map(data) do
    # Simple map encoding - encode as term
    :erlang.term_to_binary(data)
  end
  def encode(data) do
    # Fallback: encode as Erlang term
    :erlang.term_to_binary(data)
  end

  @doc """
  Decode SSZ encoded data.
  Currently returns the input or attempts binary_to_term.
  """
  def decode(data) when is_binary(data) do
    try do
      :erlang.binary_to_term(data)
    rescue
      _ -> data
    end
  end
end