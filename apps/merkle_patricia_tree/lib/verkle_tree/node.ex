defmodule VerkleTree.Node do
  @moduledoc """
  Verkle tree node implementation with 256-width nodes.
  
  Unlike Merkle Patricia Trees with 17-width nodes, verkle trees use
  256-width nodes to optimize for vector commitment efficiency.
  """

  alias VerkleTree.Crypto
  alias MerklePatriciaTree.DB

  @type commitment :: binary()
  @type node_type :: :empty | :leaf | :internal
  @type verkle_node :: 
          :empty
          | {:leaf, commitment(), binary()}  # {commitment, value}
          | {:internal, [commitment()]}      # Array of 256 child commitments

  @verkle_node_width 256

  @doc """
  Creates an empty verkle node.
  """
  @spec empty() :: verkle_node()
  def empty(), do: :empty

  @doc """
  Creates a leaf node with the given value.
  """
  @spec leaf(binary()) :: verkle_node()
  def leaf(value) do
    commitment = Crypto.commit_to_value(value)
    {:leaf, commitment, value}
  end

  @doc """
  Creates an internal node with the given child commitments.
  """
  @spec internal([commitment()]) :: verkle_node()
  def internal(children) when length(children) == @verkle_node_width do
    {:internal, children}
  end

  @doc """
  Retrieves a value from the node tree for the given key.
  """
  @spec get_value(verkle_node(), binary(), VerkleTree.t()) :: {:ok, binary()} | :not_found
  def get_value(:empty, _key, _tree), do: :not_found

  def get_value({:leaf, _commitment, value}, _key, _tree) do
    # In a simple implementation, we assume the leaf contains the value
    # In practice, you'd need to check if the key matches
    {:ok, value}
  end

  def get_value({:internal, children}, key, tree) do
    # Extract the first byte as the child index
    <<child_index, rest::binary>> = key
    
    case Enum.at(children, child_index) do
      nil -> :not_found
      <<0::256>> -> :not_found  # Empty commitment
      child_commitment ->
        # Recursively traverse to child node
        case DB.get(tree.db, child_commitment) do
          {:ok, encoded_child} ->
            child_node = decode(encoded_child)
            get_value(child_node, rest, tree)
          :not_found ->
            :not_found
        end
    end
  end

  @doc """
  Inserts or updates a value in the node tree for the given key.
  """
  @spec put_value(verkle_node(), binary(), binary(), VerkleTree.t()) :: verkle_node()
  def put_value(:empty, _key, value, _tree) do
    leaf(value)
  end

  def put_value({:leaf, _old_commitment, _old_value}, _key, value, _tree) do
    # Replace the leaf value
    # In practice, you'd need to handle key conflicts
    leaf(value)
  end

  def put_value({:internal, children}, key, value, tree) do
    <<child_index, rest::binary>> = key
    
    # Get or create child node
    child_node = case Enum.at(children, child_index) do
      nil -> empty()
      <<0::256>> -> empty()  # Empty commitment
      child_commitment ->
        case DB.get(tree.db, child_commitment) do
          {:ok, encoded_child} -> decode(encoded_child)
          :not_found -> empty()
        end
    end
    
    # Recursively update child
    updated_child = put_value(child_node, rest, value, tree)
    updated_commitment = compute_commitment(updated_child)
    
    # Store updated child
    DB.put!(tree.db, updated_commitment, encode(updated_child))
    
    # Update children array
    updated_children = List.replace_at(children, child_index, updated_commitment)
    {:internal, updated_children}
  end

  @doc """
  Removes a value from the node tree for the given key.
  """
  @spec remove_value(verkle_node(), binary(), VerkleTree.t()) :: verkle_node()
  def remove_value(:empty, _key, _tree), do: :empty

  def remove_value({:leaf, _commitment, _value}, _key, _tree) do
    # Remove the leaf
    :empty
  end

  def remove_value({:internal, children}, key, tree) do
    <<child_index, rest::binary>> = key
    
    case Enum.at(children, child_index) do
      nil -> {:internal, children}  # Key not found, no change
      <<0::256>> -> {:internal, children}  # Empty child, no change
      child_commitment ->
        case DB.get(tree.db, child_commitment) do
          {:ok, encoded_child} ->
            child_node = decode(encoded_child)
            updated_child = remove_value(child_node, rest, tree)
            
            case updated_child do
              :empty ->
                # Child became empty, set commitment to zero
                updated_children = List.replace_at(children, child_index, <<0::256>>)
                {:internal, updated_children}
              _ ->
                # Update child commitment
                updated_commitment = compute_commitment(updated_child)
                DB.put!(tree.db, updated_commitment, encode(updated_child))
                updated_children = List.replace_at(children, child_index, updated_commitment)
                {:internal, updated_children}
            end
          :not_found ->
            {:internal, children}  # Child not found, no change
        end
    end
  end

  @doc """
  Computes the cryptographic commitment for a node.
  """
  @spec compute_commitment(verkle_node()) :: commitment()
  def compute_commitment(:empty), do: <<0::256>>
  
  def compute_commitment({:leaf, commitment, _value}), do: commitment
  
  def compute_commitment({:internal, children}) do
    Crypto.commit_to_children(children)
  end

  @doc """
  Encodes a verkle node to binary format for storage.
  """
  @spec encode(verkle_node()) :: binary()
  def encode(:empty), do: <<0>>
  
  def encode({:leaf, commitment, value}) do
    value_length = byte_size(value)
    <<1, commitment::binary-size(32), value_length::32, value::binary>>
  end
  
  def encode({:internal, children}) do
    children_binary = children |> Enum.map(&(&1)) |> :erlang.list_to_binary()
    <<2, children_binary::binary>>
  end

  @doc """
  Decodes a binary-encoded verkle node.
  """
  @spec decode(binary()) :: verkle_node()
  def decode(<<0>>), do: :empty
  
  def decode(<<1, commitment::binary-size(32), value_length::32, value::binary-size(value_length)>>) do
    {:leaf, commitment, value}
  end
  
  def decode(<<2, children_binary::binary>>) do
    children = for <<child::binary-size(32) <- children_binary>>, do: child
    {:internal, children}
  end

  # Helper function to initialize empty internal node
  @spec empty_internal() :: verkle_node()
  def empty_internal() do
    children = List.duplicate(<<0::256>>, @verkle_node_width)
    {:internal, children}
  end
end