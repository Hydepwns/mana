defmodule ExWire.Eth2.Checkpoint do
  @moduledoc """
  Checkpoint representing a finalized or justified state in Ethereum 2.0.
  
  Checkpoints are used in the Casper FFG finality gadget to track
  justified and finalized epochs.
  """
  
  defstruct [
    :epoch,
    :root
  ]
  
  @type t :: %__MODULE__{
    epoch: non_neg_integer(),
    root: binary()
  }
  
  @doc """
  Create a new checkpoint.
  """
  @spec new(non_neg_integer(), binary()) :: t()
  def new(epoch, root) do
    %__MODULE__{
      epoch: epoch,
      root: root
    }
  end
  
  @doc """
  Check if this checkpoint is newer than another.
  """
  @spec newer_than?(t(), t()) :: boolean()
  def newer_than?(checkpoint1, checkpoint2) do
    checkpoint1.epoch > checkpoint2.epoch
  end
  
  @doc """
  Get the genesis checkpoint.
  """
  @spec genesis(binary()) :: t()
  def genesis(root \\ <<0::256>>) do
    %__MODULE__{
      epoch: 0,
      root: root
    }
  end
end