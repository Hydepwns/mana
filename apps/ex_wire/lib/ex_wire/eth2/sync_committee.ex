defmodule ExWire.Eth2.SyncCommittee do
  @moduledoc """
  Sync committee for Ethereum 2.0 beacon chain.

  Manages the sync committee responsible for light client synchronization.
  """

  defstruct [
    :pubkeys,
    :aggregate_pubkey
  ]

  @type t :: %__MODULE__{
          pubkeys: [binary()],
          aggregate_pubkey: binary()
        }

  @doc """
  Create a new sync committee with the given public keys.
  """
  @spec new([binary()]) :: t()
  def new(pubkeys) do
    # In production, this would compute the actual BLS aggregate pubkey
    aggregate_pubkey = :crypto.hash(:sha256, Enum.join(pubkeys))

    %__MODULE__{
      pubkeys: pubkeys,
      aggregate_pubkey: aggregate_pubkey
    }
  end

  @doc """
  Check if a validator is in the sync committee.
  """
  @spec is_member?(t(), binary()) :: boolean()
  def is_member?(sync_committee, pubkey) do
    pubkey in sync_committee.pubkeys
  end

  @doc """
  Get the size of the sync committee.
  """
  @spec size(t()) :: non_neg_integer()
  def size(sync_committee) do
    length(sync_committee.pubkeys)
  end
end
