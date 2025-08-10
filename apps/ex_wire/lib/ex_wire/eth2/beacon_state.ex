defmodule ExWire.Eth2.BeaconState do
  @moduledoc """
  Beacon Chain state representation for Ethereum 2.0.

  Contains all the state necessary for the beacon chain consensus,
  including validators, balances, checkpoints, and execution payload.
  """

  defstruct [
    # Versioning
    :genesis_time,
    :genesis_validators_root,
    :slot,
    :fork,

    # History
    :latest_block_header,
    :block_roots,
    :state_roots,
    :historical_roots,

    # Eth1 data
    :eth1_data,
    :eth1_data_votes,
    :eth1_deposit_index,

    # Registry
    :validators,
    :balances,

    # Randomness
    :randao_mixes,

    # Slashings
    :slashings,

    # Attestations
    :previous_epoch_participation,
    :current_epoch_participation,

    # Finality
    :justification_bits,
    :previous_justified_checkpoint,
    :current_justified_checkpoint,
    :finalized_checkpoint,

    # Sync committees
    :current_sync_committee,
    :next_sync_committee,

    # Execution
    :latest_execution_payload_header,

    # Withdrawals
    :next_withdrawal_index,
    :next_withdrawal_validator_index
  ]

  @type t :: %__MODULE__{
          genesis_time: non_neg_integer(),
          genesis_validators_root: binary(),
          slot: non_neg_integer(),
          fork: map(),
          latest_block_header: map(),
          block_roots: [binary()],
          state_roots: [binary()],
          historical_roots: [binary()],
          eth1_data: map(),
          eth1_data_votes: [map()],
          eth1_deposit_index: non_neg_integer(),
          validators: [map()],
          balances: [non_neg_integer()],
          randao_mixes: [binary()],
          slashings: [non_neg_integer()],
          previous_epoch_participation: [non_neg_integer()],
          current_epoch_participation: [non_neg_integer()],
          justification_bits: binary(),
          previous_justified_checkpoint: map(),
          current_justified_checkpoint: map(),
          finalized_checkpoint: map(),
          current_sync_committee: map() | nil,
          next_sync_committee: map() | nil,
          latest_execution_payload_header: map() | nil,
          next_withdrawal_index: non_neg_integer(),
          next_withdrawal_validator_index: non_neg_integer()
        }
end
