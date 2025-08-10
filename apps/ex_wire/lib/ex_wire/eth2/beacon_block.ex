defmodule ExWire.Eth2.BeaconBlock do
  @moduledoc """
  Beacon block representation for Ethereum 2.0.

  Represents a beacon block in the proof-of-stake consensus layer.
  """

  defstruct [
    :slot,
    :proposer_index,
    :parent_root,
    :state_root,
    :body
  ]

  @type t :: %__MODULE__{
          slot: non_neg_integer(),
          proposer_index: non_neg_integer(),
          parent_root: binary(),
          state_root: binary(),
          body: BeaconBlock.Body.t()
        }

  defmodule Body do
    @moduledoc """
    Beacon block body containing all block operations and data.
    """

    defstruct [
      :randao_reveal,
      :eth1_data,
      :graffiti,
      :proposer_slashings,
      :attester_slashings,
      :attestations,
      :deposits,
      :voluntary_exits,
      :sync_aggregate,
      :execution_payload,
      :bls_to_execution_changes,
      :blob_kzg_commitments
    ]

    @type t :: %__MODULE__{
            randao_reveal: binary(),
            eth1_data: map(),
            graffiti: binary(),
            proposer_slashings: [map()],
            attester_slashings: [map()],
            attestations: [map()],
            deposits: [map()],
            voluntary_exits: [map()],
            sync_aggregate: map(),
            execution_payload: map(),
            bls_to_execution_changes: [map()],
            blob_kzg_commitments: [binary()]
          }
  end
end
