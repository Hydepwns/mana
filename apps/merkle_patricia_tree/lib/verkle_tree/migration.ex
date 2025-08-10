defmodule VerkleTree.Migration do
  @moduledoc """
  State migration tools for transitioning from Merkle Patricia Trees to Verkle Trees.
  
  This module implements the transition mechanism described in EIP-6800,
  which allows for a gradual migration where:
  
  1. A new empty verkle tree is introduced alongside the existing MPT
  2. New state changes go to the verkle tree
  3. Accessed MPT state is copied to the verkle tree
  4. Eventually the MPT can be discarded
  
  This approach minimizes disruption while enabling the benefits of verkle trees.
  """

  alias MerklePatriciaTree.Trie
  alias VerkleTree
  alias MerklePatriciaTree.DB

  require Logger

  defstruct mpt: nil,
            verkle: nil,
            db: nil,
            migration_progress: 0,
            total_keys: 0

  @type t :: %__MODULE__{
          mpt: Trie.t(),
          verkle: VerkleTree.t(),
          db: DB.db(),
          migration_progress: non_neg_integer(),
          total_keys: non_neg_integer()
        }

  @doc """
  Initializes a new migration context.
  """
  @spec new(Trie.t(), DB.db()) :: t()
  def new(existing_mpt, db) do
    verkle = VerkleTree.new(db)
    
    %__MODULE__{
      mpt: existing_mpt,
      verkle: verkle,
      db: db,
      migration_progress: 0,
      total_keys: estimate_mpt_size(existing_mpt)
    }
  end

  @doc """
  Handles a state access during the transition period.
  
  This implements the EIP-6800 behavior:
  1. First check the verkle tree
  2. If not found, check the MPT
  3. If found in MPT, copy to verkle tree for future access
  """
  @spec get_with_migration(t(), binary()) :: {{:ok, binary()} | :not_found, t()}
  def get_with_migration(migration_state, key) do
    # First try verkle tree
    case VerkleTree.get(migration_state.verkle, key) do
      {:ok, value} ->
        # Found in verkle tree
        {{:ok, value}, migration_state}
      
      :not_found ->
        # Try MPT
        case Trie.get_key(migration_state.mpt, key) do
          nil ->
            {:not_found, migration_state}
          value ->
            # Found in MPT, migrate to verkle
            Logger.debug("Migrating key on access: #{inspect key}")
            
            updated_verkle = VerkleTree.put(migration_state.verkle, key, value)
            updated_state = %{migration_state | 
              verkle: updated_verkle,
              migration_progress: migration_state.migration_progress + 1
            }
            
            {{:ok, value}, updated_state}
        end
    end
  end

  @doc """
  Updates state during the transition period.
  All new updates go directly to the verkle tree.
  """
  @spec put_with_migration(t(), binary(), binary()) :: t()
  def put_with_migration(migration_state, key, value) do
    updated_verkle = VerkleTree.put(migration_state.verkle, key, value)
    
    %{migration_state | verkle: updated_verkle}
  end

  @doc """
  Removes a key during the transition period.
  Removes from both trees to ensure consistency.
  """
  @spec remove_with_migration(t(), binary()) :: t()
  def remove_with_migration(migration_state, key) do
    updated_verkle = VerkleTree.remove(migration_state.verkle, key)
    updated_mpt = Trie.remove_key(migration_state.mpt, key)
    
    %{migration_state | 
      verkle: updated_verkle,
      mpt: updated_mpt
    }
  end

  @doc """
  Performs batch migration of keys from MPT to verkle tree.
  This can be used to proactively migrate state during low-activity periods.
  """
  @spec batch_migrate(t(), [binary()], non_neg_integer()) :: {:ok, t()} | {:error, term()}
  def batch_migrate(migration_state, keys, batch_size \\ 1000) do
    keys
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce_while({:ok, migration_state}, fn batch, {:ok, state} ->
      case migrate_batch(state, batch) do
        {:ok, updated_state} ->
          {:cont, {:ok, updated_state}}
        error ->
          {:halt, error}
      end
    end)
  end

  @doc """
  Returns the migration progress as a percentage.
  """
  @spec migration_progress(t()) :: float()
  def migration_progress(migration_state) do
    if migration_state.total_keys == 0 do
      100.0
    else
      (migration_state.migration_progress / migration_state.total_keys) * 100.0
    end
  end

  @doc """
  Checks if the migration is complete.
  Migration is complete when all accessed state has been moved to the verkle tree.
  """
  @spec migration_complete?(t()) :: boolean()
  def migration_complete?(migration_state) do
    # In practice, you might define completion differently
    # For now, we consider it complete when progress reaches 100%
    migration_progress(migration_state) >= 100.0
  end

  @doc """
  Generates a unified witness that can prove state in both trees.
  This is useful during the transition period where state might be in either tree.
  """
  @spec generate_transition_witness(t(), [binary()]) :: VerkleTree.Witness.t()
  def generate_transition_witness(migration_state, keys) do
    # For now, only generate verkle witnesses
    # In a full implementation, this might need to handle MPT proofs as well
    VerkleTree.generate_witness(migration_state.verkle, keys)
  end

  @doc """
  Exports the current verkle tree state for backup or analysis.
  """
  @spec export_verkle_state(t()) :: {:ok, binary()} | {:error, term()}
  def export_verkle_state(migration_state) do
    try do
      # Export root commitment and essential metadata
      state_data = %{
        root_commitment: migration_state.verkle.root_commitment,
        migration_progress: migration_state.migration_progress,
        total_keys: migration_state.total_keys
      }
      
      {:ok, :erlang.term_to_binary(state_data)}
    rescue
      error -> {:error, error}
    end
  end

  @doc """
  Validates the consistency between MPT and verkle tree states.
  This is useful for testing and ensuring the migration is working correctly.
  """
  @spec validate_consistency(t(), [binary()]) :: {:ok, [binary()]} | {:error, [binary()]}
  def validate_consistency(migration_state, sample_keys) do
    inconsistent_keys = 
      sample_keys
      |> Enum.filter(fn key ->
        mpt_value = Trie.get_key(migration_state.mpt, key)
        
        verkle_value = case VerkleTree.get(migration_state.verkle, key) do
          {:ok, value} -> value
          :not_found -> nil
        end
        
        # Keys are inconsistent if they exist in both but have different values
        not is_nil(mpt_value) and not is_nil(verkle_value) and mpt_value != verkle_value
      end)

    case inconsistent_keys do
      [] -> {:ok, []}
      keys -> {:error, keys}
    end
  end

  # Private helper functions

  defp migrate_batch(migration_state, keys) do
    try do
      updated_state = 
        keys
        |> Enum.reduce(migration_state, fn key, acc_state ->
          case Trie.get_key(acc_state.mpt, key) do
            nil ->
              acc_state
            value ->
              updated_verkle = VerkleTree.put(acc_state.verkle, key, value)
              %{acc_state | 
                verkle: updated_verkle,
                migration_progress: acc_state.migration_progress + 1
              }
          end
        end)

      {:ok, updated_state}
    rescue
      error -> {:error, error}
    end
  end

  defp estimate_mpt_size(mpt) do
    # Placeholder: In practice, you'd need to traverse the MPT to count keys
    # This could be expensive, so you might want to cache this value
    # or estimate based on other metrics
    10000  # Placeholder value
  end
end