defmodule ExWire.Eth2.Attestation do
  @moduledoc """
  Attestation structure for Ethereum 2.0 beacon chain.
  
  Represents validator attestations to beacon blocks.
  """
  
  defstruct [
    :aggregation_bits,
    :data,
    :signature
  ]
  
  @type t :: %__MODULE__{
    aggregation_bits: binary(),
    data: AttestationData.t(),
    signature: binary()
  }
  
  defmodule AttestationData do
    @moduledoc """
    Attestation data containing the core information being attested to.
    """
    
    defstruct [
      :slot,
      :index,
      :beacon_block_root,
      :source,
      :target
    ]
    
    @type t :: %__MODULE__{
      slot: non_neg_integer(),
      index: non_neg_integer(),
      beacon_block_root: binary(),
      source: Checkpoint.t(),
      target: Checkpoint.t()
    }
  end
  
  defmodule Checkpoint do
    @moduledoc """
    Checkpoint representing a finalized or justified state.
    """
    
    defstruct [
      :epoch,
      :root
    ]
    
    @type t :: %__MODULE__{
      epoch: non_neg_integer(),
      root: binary()
    }
  end
end