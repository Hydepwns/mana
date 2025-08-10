defmodule ExWire.Eth2.ValidatorRegistry do
  @moduledoc """
  Validator registry for Ethereum 2.0 beacon chain.
  
  Manages validator information, duties, and state transitions.
  """
  
  defstruct [
    :validators,
    :balances,
    :registry_updates,
    :exit_queue,
    :activation_queue
  ]
  
  @type t :: %__MODULE__{
    validators: [map()],
    balances: [non_neg_integer()],
    registry_updates: [map()],
    exit_queue: [non_neg_integer()],
    activation_queue: [non_neg_integer()]
  }
  
  @doc """
  Initialize empty validator registry
  """
  def init do
    %__MODULE__{
      validators: [],
      balances: [],
      registry_updates: [],
      exit_queue: [],
      activation_queue: []
    }
  end
  
  @doc """
  Add validator to registry
  """
  def add_validator(registry, validator, balance \\ 0) do
    %{registry |
      validators: registry.validators ++ [validator],
      balances: registry.balances ++ [balance]
    }
  end
  
  @doc """
  Get validator by index
  """
  def get_validator(registry, index) do
    Enum.at(registry.validators, index)
  end
  
  @doc """
  Update validator balance
  """
  def update_balance(registry, index, new_balance) do
    new_balances = List.replace_at(registry.balances, index, new_balance)
    %{registry | balances: new_balances}
  end
  
  @doc """
  Get total validator count
  """
  def count(registry) do
    length(registry.validators)
  end
  
  @doc """
  Get active validators for epoch
  """
  def get_active_validators(registry, epoch) do
    registry.validators
    |> Enum.with_index()
    |> Enum.filter(fn {validator, _index} ->
      is_active_validator?(validator, epoch)
    end)
  end
  
  defp is_active_validator?(validator, epoch) do
    activation_epoch = Map.get(validator, :activation_epoch, 0)
    exit_epoch = Map.get(validator, :exit_epoch, :infinity)
    
    activation_epoch <= epoch && (exit_epoch == :infinity || epoch < exit_epoch)
  end
end