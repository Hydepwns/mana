defmodule MerklePatriciaTree.StateManager.ReferenceCounter do
  @moduledoc """
  Reference counting system for state tree nodes to track which nodes
  are still referenced and which can be safely pruned.
  """

  @typedoc "Reference counter state"
  @type t :: %__MODULE__{
          references: %{binary() => non_neg_integer()},
          root_to_nodes: %{binary() => MapSet.t(binary())},
          node_to_roots: %{binary() => MapSet.t(binary())},
          last_cleanup: DateTime.t()
        }

  defstruct [
    :references,
    :root_to_nodes,
    :node_to_roots,
    :last_cleanup
  ]

  @doc """
  Create a new reference counter.
  """
  @spec new() :: t()
  def new() do
    %__MODULE__{
      references: %{},
      root_to_nodes: %{},
      node_to_roots: %{},
      last_cleanup: DateTime.utc_now()
    }
  end

  @doc """
  Increment reference count for a state root and all its nodes.
  """
  @spec increment(t(), binary()) :: t()
  def increment(counter, state_root) do
    # Get all nodes in this state tree
    nodes = get_trie_nodes(state_root)

    # Increment references for all nodes
    new_references =
      Enum.reduce(nodes, counter.references, fn node_hash, acc ->
        Map.update(acc, node_hash, 1, &(&1 + 1))
      end)

    # Track which nodes belong to this root
    new_root_to_nodes = Map.put(counter.root_to_nodes, state_root, MapSet.new(nodes))

    # Track which roots reference each node
    new_node_to_roots =
      Enum.reduce(nodes, counter.node_to_roots, fn node_hash, acc ->
        Map.update(acc, node_hash, MapSet.new([state_root]), &MapSet.put(&1, state_root))
      end)

    %{
      counter
      | references: new_references,
        root_to_nodes: new_root_to_nodes,
        node_to_roots: new_node_to_roots
    }
  end

  @doc """
  Decrement reference count for a state root and all its nodes.
  """
  @spec decrement(t(), binary()) :: t()
  def decrement(counter, state_root) do
    case Map.get(counter.root_to_nodes, state_root) do
      nil ->
        # Root not tracked
        counter

      nodes ->
        # Decrement references for all nodes
        new_references =
          Enum.reduce(nodes, counter.references, fn node_hash, acc ->
            case Map.get(acc, node_hash, 0) do
              count when count <= 1 ->
                Map.delete(acc, node_hash)

              count ->
                Map.put(acc, node_hash, count - 1)
            end
          end)

        # Remove root from tracking
        new_root_to_nodes = Map.delete(counter.root_to_nodes, state_root)

        # Remove root from node mappings
        new_node_to_roots =
          Enum.reduce(nodes, counter.node_to_roots, fn node_hash, acc ->
            case Map.get(acc, node_hash) do
              nil ->
                acc

              root_set ->
                new_set = MapSet.delete(root_set, state_root)

                if MapSet.size(new_set) == 0 do
                  Map.delete(acc, node_hash)
                else
                  Map.put(acc, node_hash, new_set)
                end
            end
          end)

        %{
          counter
          | references: new_references,
            root_to_nodes: new_root_to_nodes,
            node_to_roots: new_node_to_roots
        }
    end
  end

  @doc """
  Get reference count for a specific node or state root.
  """
  @spec get_references(t(), binary()) :: non_neg_integer()
  def get_references(counter, hash) do
    Map.get(counter.references, hash, 0)
  end

  @doc """
  Get all state roots that have zero references.
  """
  @spec get_unreferenced_roots(t()) :: [binary()]
  def get_unreferenced_roots(counter) do
    counter.root_to_nodes
    |> Map.keys()
    |> Enum.filter(fn root ->
      Map.get(counter.references, root, 0) == 0
    end)
  end

  @doc """
  Get all nodes that have zero references.
  """
  @spec get_unreferenced_nodes(t()) :: [binary()]
  def get_unreferenced_nodes(counter) do
    counter.references
    |> Enum.filter(fn {_hash, count} -> count == 0 end)
    |> Enum.map(fn {hash, _count} -> hash end)
  end

  @doc """
  Remove multiple roots from tracking.
  """
  @spec remove_roots(t(), [binary()]) :: t()
  def remove_roots(counter, roots) do
    Enum.reduce(roots, counter, fn root, acc ->
      decrement(acc, root)
    end)
  end

  @doc """
  Get statistics about the reference counter.
  """
  @spec get_stats(t()) :: %{
          total_roots: non_neg_integer(),
          total_nodes: non_neg_integer(),
          unreferenced_roots: non_neg_integer(),
          unreferenced_nodes: non_neg_integer(),
          avg_references_per_node: float()
        }
  def get_stats(counter) do
    total_nodes = map_size(counter.references)
    total_refs = counter.references |> Map.values() |> Enum.sum()

    %{
      total_roots: map_size(counter.root_to_nodes),
      total_nodes: total_nodes,
      unreferenced_roots: length(get_unreferenced_roots(counter)),
      unreferenced_nodes: length(get_unreferenced_nodes(counter)),
      avg_references_per_node: if(total_nodes > 0, do: total_refs / total_nodes, else: 0.0)
    }
  end

  @doc """
  Convert reference counter to a map for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(counter) do
    %{
      references: counter.references,
      root_to_nodes: Map.new(counter.root_to_nodes, fn {k, v} -> {k, MapSet.to_list(v)} end),
      node_to_roots: Map.new(counter.node_to_roots, fn {k, v} -> {k, MapSet.to_list(v)} end),
      last_cleanup: counter.last_cleanup
    }
  end

  @doc """
  Create reference counter from a map (deserialization).
  """
  @spec from_map(map()) :: t()
  def from_map(data) do
    %__MODULE__{
      references: Map.get(data, :references, %{}),
      root_to_nodes:
        Map.new(Map.get(data, :root_to_nodes, %{}), fn {k, v} -> {k, MapSet.new(v)} end),
      node_to_roots:
        Map.new(Map.get(data, :node_to_roots, %{}), fn {k, v} -> {k, MapSet.new(v)} end),
      last_cleanup: Map.get(data, :last_cleanup, DateTime.utc_now())
    }
  end

  @doc """
  Cleanup stale references and optimize data structures.
  """
  @spec cleanup(t()) :: t()
  def cleanup(counter) do
    # Remove any inconsistent references
    valid_references =
      counter.references
      |> Enum.filter(fn {_hash, count} -> count > 0 end)
      |> Map.new()

    # Clean up mapping tables
    valid_node_to_roots =
      counter.node_to_roots
      |> Enum.filter(fn {hash, _roots} -> Map.has_key?(valid_references, hash) end)
      |> Map.new()

    valid_root_to_nodes =
      counter.root_to_nodes
      |> Enum.filter(fn {root, _nodes} -> Map.has_key?(valid_references, root) end)
      |> Map.new()

    %{
      counter
      | references: valid_references,
        root_to_nodes: valid_root_to_nodes,
        node_to_roots: valid_node_to_roots,
        last_cleanup: DateTime.utc_now()
    }
  end

  # Private helper functions

  defp get_trie_nodes(state_root) do
    # In a real implementation, this would traverse the trie
    # and collect all node hashes. For now, we'll simulate this.

    # Generate some fake node hashes for testing
    # In production, this would use MerklePatriciaTree.Trie traversal
    base_nodes =
      for i <- 1..10 do
        :crypto.hash(:sha256, state_root <> <<i>>)
      end

    [state_root | base_nodes]
  end
end
