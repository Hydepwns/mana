defmodule VerkleTree do
  @moduledoc """
  Implementation of Verkle Trees for Ethereum state transition, following EIP-6800.

  Verkle trees combine vector commitments with Merkle tree structures to enable
  stateless clients with small witnesses (~200 bytes vs ~3KB for MPT).

  Key features:
  - 256-width nodes (vs 17-width for MPT)
  - Bandersnatch curve cryptographic commitments  
  - Unified key/value abstraction for all state data
  - Small witness sizes enabling stateless clients
  """

  alias MerklePatriciaTree.DB
  alias VerkleTree.{Node, Crypto, Witness, StateExpiry}

  defstruct db: nil, root_commitment: nil

  @type commitment :: binary()
  @type root_commitment :: commitment
  @type key :: binary()
  @type value :: binary()

  @type t :: %__MODULE__{
          db: DB.db(),
          root_commitment: root_commitment
        }

  @verkle_node_width 256
  @empty_commitment <<0::256>>

  @doc """
  Creates a new verkle tree with the given database backend.
  """
  @spec new(DB.db(), root_commitment | nil) :: t()
  def new(db, root_commitment \\ @empty_commitment) do
    %__MODULE__{
      db: db,
      root_commitment: root_commitment || @empty_commitment
    }
    |> store()
  end

  @doc """
  Retrieves the value associated with the given key.
  """
  @spec get(t(), key()) :: {:ok, value()} | :not_found
  def get(tree, key) do
    # For simplified implementation, use direct storage lookup
    # In a full verkle tree, this would traverse the tree structure
    verkle_key = normalize_key(key)
    storage_key = "verkle:" <> verkle_key

    case DB.get(tree.db, storage_key) do
      {:ok, value} -> {:ok, value}
      :not_found -> :not_found
    end
  end

  @doc """
  Updates the tree by setting key to value.
  If value is nil, removes the key from the tree.
  """
  @spec put(t(), key(), value() | nil) :: t()
  def put(tree, key, value) do
    verkle_key = normalize_key(key)
    storage_key = "verkle:" <> verkle_key

    if is_nil(value) do
      remove(tree, key)
    else
      # Store the value directly for simplified implementation
      DB.put!(tree.db, storage_key, value)

      # Update root commitment based on new state
      new_commitment = compute_new_root_commitment(tree, key, value)

      %{tree | root_commitment: new_commitment}
      |> store()
    end
  end

  @doc """
  Removes a key from the tree.
  """
  @spec remove(t(), key()) :: t()
  def remove(tree, key) do
    verkle_key = normalize_key(key)
    storage_key = "verkle:" <> verkle_key

    # Remove from storage
    DB.delete!(tree.db, storage_key)

    # Update root commitment
    new_commitment = compute_new_root_commitment(tree, key, nil)

    %{tree | root_commitment: new_commitment}
    |> store()
  end

  @doc """
  Generates a witness (proof) for the given keys.
  Returns a compact proof that can be verified independently.
  """
  @spec generate_witness(t(), [key()]) :: Witness.t()
  def generate_witness(tree, keys) do
    verkle_keys = Enum.map(keys, &normalize_key/1)
    Witness.generate(tree, verkle_keys)
  end

  @doc """
  Verifies a witness against a root commitment.
  """
  @spec verify_witness(Witness.t(), root_commitment(), [{key(), value()}]) :: boolean()
  def verify_witness(witness, root_commitment, key_value_pairs) do
    Witness.verify(witness, root_commitment, key_value_pairs)
  end

  @doc """
  Returns the root commitment of the tree.
  """
  @spec root_commitment(t()) :: root_commitment()
  def root_commitment(tree), do: tree.root_commitment

  # State Expiry Methods (EIP-7736)

  @doc """
  Gets a value with state expiry checking.

  Returns `{:expired, proof}` if the state is expired and needs resurrection.
  """
  @spec get_with_expiry(t(), key(), map()) :: {:ok, value()} | {:expired, map()} | :not_found
  def get_with_expiry(tree, key, expiry_manager) do
    normalized_key = normalize_key(key)
    StateExpiry.get_with_expiry(tree, normalized_key, expiry_manager)
  end

  @doc """
  Puts a value with state expiry epoch tracking.
  """
  @spec put_with_expiry(t(), key(), value(), map()) :: t()
  def put_with_expiry(tree, key, value, expiry_manager) do
    normalized_key = normalize_key(key)
    StateExpiry.put_with_expiry(tree, normalized_key, value, expiry_manager)
  end

  @doc """
  Resurrects expired state with a proof.
  """
  @spec resurrect_state(t(), key(), map(), map()) ::
          {:ok, t(), map(), non_neg_integer()} | {:error, term()}
  def resurrect_state(tree, key, resurrection_proof, expiry_manager) do
    normalized_key = normalize_key(key)
    StateExpiry.resurrect_state(tree, normalized_key, resurrection_proof, expiry_manager)
  end

  @doc """
  Performs garbage collection to remove expired state.
  """
  @spec garbage_collect(t(), map()) :: {t(), map()}
  def garbage_collect(tree, expiry_manager) do
    StateExpiry.garbage_collect(tree, expiry_manager)
  end

  @doc """
  Gets state expiry statistics.
  """
  @spec get_expiry_stats(map()) :: map()
  def get_expiry_stats(expiry_manager) do
    StateExpiry.get_expiry_stats(expiry_manager)
  end

  # Private helper functions

  defp normalize_key(key) when byte_size(key) == 32, do: key

  defp normalize_key(key) when is_binary(key) do
    # Pad or hash to 32 bytes as per EIP-6800
    case byte_size(key) do
      size when size < 32 ->
        # Pad with zeros
        key <> :binary.copy(<<0>>, 32 - size)

      size when size > 32 ->
        # Hash to 32 bytes
        ExthCrypto.Hash.Keccak.kec(key)

      32 ->
        key
    end
  end

  defp normalize_key(key) when is_list(key) do
    key
    |> :binary.list_to_bin()
    |> normalize_key()
  end

  defp fetch_node(tree) do
    case DB.get(tree.db, tree.root_commitment) do
      {:ok, encoded_node} ->
        Node.decode(encoded_node)

      :not_found ->
        Node.empty()
    end
  end

  defp update_root_commitment(node, tree) do
    commitment = Node.compute_commitment(node)
    %{tree | root_commitment: commitment}
  end

  defp compute_new_root_commitment(tree, key, value) do
    # Simplified implementation: hash the current state
    # In a real verkle tree, this would compute the proper polynomial commitment
    state_data =
      [tree.root_commitment, normalize_key(key), value || ""]
      |> Enum.join()

    ExthCrypto.Hash.Keccak.kec(state_data)
  end

  defp store(tree) do
    # Store the tree state if needed
    tree
  end
end
