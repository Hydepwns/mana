defmodule ExWire.Eth2.ExecutionPayload do
  @moduledoc """
  Execution payload for Ethereum 2.0 beacon blocks.
  
  Contains the execution layer block data that is committed to
  by the beacon chain consensus layer.
  """
  
  defstruct [
    :parent_hash,
    :fee_recipient,
    :state_root,
    :receipts_root,
    :logs_bloom,
    :prev_randao,
    :block_number,
    :gas_limit,
    :gas_used,
    :timestamp,
    :extra_data,
    :base_fee_per_gas,
    :block_hash,
    :transactions,
    :withdrawals,
    :blob_gas_used,
    :excess_blob_gas
  ]
  
  @type t :: %__MODULE__{
    parent_hash: binary(),
    fee_recipient: binary(),
    state_root: binary(),
    receipts_root: binary(),
    logs_bloom: binary(),
    prev_randao: binary(),
    block_number: non_neg_integer(),
    gas_limit: non_neg_integer(),
    gas_used: non_neg_integer(),
    timestamp: non_neg_integer(),
    extra_data: binary(),
    base_fee_per_gas: non_neg_integer(),
    block_hash: binary(),
    transactions: [binary()],
    withdrawals: [map()],
    blob_gas_used: non_neg_integer(),
    excess_blob_gas: non_neg_integer()
  }
  
  @doc """
  Create an empty execution payload.
  """
  @spec empty() :: t()
  def empty do
    %__MODULE__{
      parent_hash: <<0::256>>,
      fee_recipient: <<0::160>>,
      state_root: <<0::256>>,
      receipts_root: <<0::256>>,
      logs_bloom: <<0::2048>>,
      prev_randao: <<0::256>>,
      block_number: 0,
      gas_limit: 0,
      gas_used: 0,
      timestamp: 0,
      extra_data: <<>>,
      base_fee_per_gas: 0,
      block_hash: <<0::256>>,
      transactions: [],
      withdrawals: [],
      blob_gas_used: 0,
      excess_blob_gas: 0
    }
  end
  
  @doc """
  Check if the execution payload contains blob transactions.
  """
  @spec has_blobs?(t()) :: boolean()
  def has_blobs?(payload) do
    payload.blob_gas_used > 0
  end
end