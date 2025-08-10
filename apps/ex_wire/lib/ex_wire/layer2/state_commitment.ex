defmodule ExWire.Layer2.StateCommitment do
  @moduledoc """
  State commitment computation for Layer 2 rollups.
  Handles merkle tree construction and state root calculation.
  """

  alias ExWire.Layer2.Batch

  @doc """
  Computes the new state root after applying a batch.
  """
  @spec compute_root(Batch.t(), binary()) :: {:ok, binary()} | {:error, term()}
  def compute_root(batch, previous_root) do
    try do
      # Start with previous state root
      state_hash = previous_root
      
      # Apply each transaction to compute new state
      new_state_hash = Enum.reduce(batch.transactions, state_hash, fn tx, acc ->
        apply_transaction(tx, acc)
      end)
      
      # Include batch metadata in final root
      final_root = compute_final_root(new_state_hash, batch)
      
      {:ok, final_root}
    rescue
      e -> {:error, e}
    end
  end

  @doc """
  Verifies a state commitment against expected root.
  """
  @spec verify_commitment(binary(), binary(), list(binary())) :: boolean()
  def verify_commitment(leaf, root, proof) do
    computed_root = Enum.reduce(proof, leaf, fn sibling, acc ->
      if acc < sibling do
        hash_pair(acc, sibling)
      else
        hash_pair(sibling, acc)
      end
    end)
    
    computed_root == root
  end

  @doc """
  Generates a merkle proof for a value in the state tree.
  """
  @spec generate_proof(binary(), list(binary())) :: list(binary())
  def generate_proof(leaf_index, tree_leaves) do
    # Build merkle tree
    tree = build_merkle_tree(tree_leaves)
    
    # Extract proof path
    extract_proof_path(tree, leaf_index)
  end

  @doc """
  Computes the merkle root of a list of values.
  """
  @spec merkle_root(list(binary())) :: binary()
  def merkle_root([]), do: <<0::256>>
  def merkle_root([single]), do: single
  def merkle_root(leaves) do
    # Pad to power of 2
    padded_leaves = pad_to_power_of_two(leaves)
    
    # Build tree bottom-up
    build_tree_root(padded_leaves)
  end

  # Private Functions

  defp apply_transaction(tx, state_hash) do
    # Simulate state transition
    # In production, this would apply the actual state changes
    tx_data = :erlang.term_to_binary(tx)
    combined = state_hash <> tx_data
    :crypto.hash(:sha256, combined)
  end

  defp compute_final_root(state_hash, batch) do
    # Combine state hash with batch metadata
    batch_data = <<
      batch.number::64,
      batch.timestamp |> DateTime.to_unix()::64
    >>
    
    combined = state_hash <> batch_data <> batch.sequencer
    :crypto.hash(:sha256, combined)
  end

  defp hash_pair(left, right) do
    :crypto.hash(:sha256, left <> right)
  end

  defp build_merkle_tree(leaves) do
    padded = pad_to_power_of_two(leaves)
    build_tree_layers([padded])
  end

  defp build_tree_layers(layers = [layer | _]) when length(layer) == 1 do
    layers
  end

  defp build_tree_layers([current_layer | _] = layers) do
    next_layer = current_layer
                 |> Enum.chunk_every(2)
                 |> Enum.map(fn
                   [left, right] -> hash_pair(left, right)
                   [single] -> single
                 end)
    
    build_tree_layers([next_layer | layers])
  end

  defp extract_proof_path(tree, leaf_index) do
    # Extract sibling hashes along the path to root
    Enum.reduce(tree, {leaf_index, []}, fn layer, {idx, proof} ->
      sibling_idx = if rem(idx, 2) == 0, do: idx + 1, else: idx - 1
      
      sibling = if sibling_idx < length(layer) do
        Enum.at(layer, sibling_idx)
      else
        Enum.at(layer, idx)  # No sibling, use self
      end
      
      {div(idx, 2), [sibling | proof]}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp pad_to_power_of_two(leaves) do
    count = length(leaves)
    target = next_power_of_two(count)
    padding_needed = target - count
    
    if padding_needed > 0 do
      padding = List.duplicate(<<0::256>>, padding_needed)
      leaves ++ padding
    else
      leaves
    end
  end

  defp next_power_of_two(n) do
    :math.pow(2, :math.ceil(:math.log2(max(n, 1))))
    |> round()
  end

  defp build_tree_root(leaves) when length(leaves) == 1 do
    hd(leaves)
  end

  defp build_tree_root(leaves) do
    next_level = leaves
                 |> Enum.chunk_every(2)
                 |> Enum.map(fn
                   [left, right] -> hash_pair(left, right)
                   [single] -> single
                 end)
    
    build_tree_root(next_level)
  end
end