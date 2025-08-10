defmodule ExWire.Layer2.Batch do
  @moduledoc """
  Batch structure for Layer 2 rollups.
  Represents a collection of transactions to be processed together.
  """

  @type t :: %__MODULE__{
          number: non_neg_integer(),
          transactions: list(map()),
          state_root: binary(),
          previous_root: binary(),
          timestamp: DateTime.t(),
          sequencer: binary(),
          signature: binary() | nil
        }

  defstruct [
    :number,
    :transactions,
    :state_root,
    :previous_root,
    :timestamp,
    :sequencer,
    :signature
  ]

  @doc """
  Creates a new batch.
  """
  def new(number, transactions, previous_root, sequencer) do
    %__MODULE__{
      number: number,
      transactions: transactions,
      previous_root: previous_root,
      timestamp: DateTime.utc_now(),
      sequencer: sequencer
    }
  end

  @doc """
  Computes the hash of a batch.
  """
  def hash(batch) do
    data = :erlang.term_to_binary(%{
      number: batch.number,
      transactions: batch.transactions,
      state_root: batch.state_root,
      previous_root: batch.previous_root,
      timestamp: batch.timestamp,
      sequencer: batch.sequencer
    })
    
    :crypto.hash(:sha256, data)
  end

  @doc """
  Signs a batch with a private key.
  """
  def sign(batch, private_key) do
    hash = hash(batch)
    signature = :crypto.sign(:ecdsa, :sha256, hash, [private_key, :secp256k1])
    %{batch | signature: signature}
  end

  @doc """
  Verifies a batch signature.
  """
  def verify_signature(batch, public_key) do
    if batch.signature do
      hash = hash(batch)
      :crypto.verify(:ecdsa, :sha256, hash, batch.signature, [public_key, :secp256k1])
    else
      false
    end
  end

  @doc """
  Encodes a batch for transmission.
  """
  def encode(batch) do
    :erlang.term_to_binary(batch)
  end

  @doc """
  Decodes a batch from binary.
  """
  def decode(binary) do
    :erlang.binary_to_term(binary)
  end
end