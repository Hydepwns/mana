defmodule MerklePatriciaTree.Trie.Storage do
  @moduledoc """
  Module to get and put nodes in a trie by the given
  storage mechanism. Generally, handles the function `n(I, i)`,
  Eq.(178) from the Yellow Paper.
  """

  alias ExthCrypto.Hash.Keccak
  alias MerklePatriciaTree.{DB, Trie}

  # Maximum RLP length in bytes that is stored as is
  @max_rlp_len 32
  @type max_rlp_len :: unquote(@max_rlp_len)

  @spec max_rlp_len() :: max_rlp_len()
  def max_rlp_len(), do: @max_rlp_len

  # Keccak-256 is always 32-bytes.
  def keccak_hash?(bytes), do: byte_size(bytes) < max_rlp_len()

  @doc """
  Takes an RLP-encoded node and pushes it to storage,
  as defined by `n(I, i)` Eq.(178) of the Yellow Paper.

  Specifically, Eq.(178) says that the node is encoded as `c(J,i)` in the second
  portion of the definition of `n`. By the definition of `c`, all return values are
  RLP encoded. But, we have found emperically that the `n` does not encode values to
  RLP for smaller nodes.

  ## Examples

      iex> trie = MerklePatriciaTree.Trie.new(MerklePatriciaTree.Test.random_ets_db())
      iex> MerklePatriciaTree.Trie.Storage.put_node(<<>>, trie)
      <<>>
      iex> MerklePatriciaTree.Trie.Storage.put_node("Hi", trie)
      "Hi"
      # TODO: This is SHA-256 hash, not Keccak-256, due to keccakf1600 being unavailable
      iex> MerklePatriciaTree.Trie.Storage.put_node(["AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"], trie)
      <<232, 190, 32, 99, 170, 173, 188, 188, 109, 118, 25, 64, 129, 91,
             206, 250, 152, 20, 34, 121, 94, 226, 6, 47, 12, 143,
             11, 106, 197, 56, 141, 47>>
  """
  @spec put_node(ExRLP.t(), Trie.t()) :: binary()
  def put_node(rlp, trie) do
    case ExRLP.encode(rlp) do
      # Store large nodes
      encoded when byte_size(encoded) >= @max_rlp_len ->
        store(encoded, trie.db)

      # Otherwise, return node itself
      _ ->
        rlp
    end
  end

  @doc """
  Takes an RLP-encoded node, calculates Keccak-256 hash of it
  and stores it in the DB.

  ## Examples

      # TODO: These are SHA-256 hashes, not Keccak-256, due to keccakf1600 being unavailable
      iex> db = MerklePatriciaTree.Test.random_ets_db()
      iex> empty = ExRLP.encode(<<>>)
      iex> MerklePatriciaTree.Trie.Storage.store(empty, db)
      <<118, 190, 139, 82, 141, 0, 117, 247, 170, 233, 141, 111, 165, 122,
            109, 60, 131, 174, 72, 10, 132, 105, 230, 104, 215,
            176, 175, 150, 137, 149, 172, 113>>
      iex> foo = ExRLP.encode("foo")
      iex> MerklePatriciaTree.Trie.Storage.store(foo, db)
      <<241, 206, 14, 156, 156, 247, 90, 202, 36, 23, 131, 152, 60, 225, 127,
            195, 240, 113, 19, 201, 163, 220, 5, 12, 143, 23, 177, 226, 157, 92, 23, 33>>
  """
  @spec store(ExRLP.t(), MerklePatriciaTree.DB.db()) :: binary()
  def store(rlp_encoded_node, db) do
    # SHA3
    node_hash = Keccak.kec(rlp_encoded_node)

    # Store in db
    DB.put!(db, node_hash, rlp_encoded_node)

    # Return hash
    node_hash
  end

  def delete(trie = %{root_hash: h})
      when not is_binary(h) or h == <<>>,
      do: trie

  def delete(trie), do: DB.delete!(trie.db, trie.root_hash)

  @doc """
  Gets the RLP encoded value of a given trie root. Specifically,
  we invert the function `n(I, i)` Eq.(178) from the Yellow Paper.

  ## Examples

      iex> MerklePatriciaTree.Trie.new(MerklePatriciaTree.Test.random_ets_db(), <<>>)
      ...> |> MerklePatriciaTree.Trie.Storage.get_node()
      <<>>

      iex> MerklePatriciaTree.Trie.new(MerklePatriciaTree.Test.random_ets_db(), <<130, 72, 105>>)
      ...> |> MerklePatriciaTree.Trie.Storage.get_node()
      "Hi"

      iex> MerklePatriciaTree.Trie.new(MerklePatriciaTree.Test.random_ets_db(), <<254, 112, 17, 90, 21, 82, 19, 29, 72, 106, 175, 110, 87, 220, 249, 140, 74, 165, 64, 94, 174, 79, 78, 189, 145, 143, 92, 53, 173, 136, 220, 145>>)
      ...> |> MerklePatriciaTree.Trie.Storage.get_node()
      :not_found

      # TODO: This is SHA-256 hash, not Keccak-256, due to keccakf1600 being unavailable
      iex> trie = MerklePatriciaTree.Trie.new(MerklePatriciaTree.Test.random_ets_db(), <<130, 72, 105>>)
      iex> MerklePatriciaTree.Trie.Storage.put_node(["AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"], trie)
      <<232, 190, 32, 99, 170, 173, 188, 188, 109, 118, 25, 64, 129, 91,
        206, 250, 152, 20, 34, 121, 94, 226, 6, 47, 12, 143,
        11, 106, 197, 56, 141, 47>>
      iex> MerklePatriciaTree.Trie.Storage.get_node(%{trie| root_hash: <<232, 190, 32, 99, 170, 173, 188, 188, 109, 118, 25, 64, 129, 91, 206, 250, 152, 20, 34, 121, 94, 226, 6, 47, 12, 143, 11, 106, 197, 56, 141, 47>>})
      ["AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"]
  """
  @spec get_node(Trie.t()) :: ExRLP.t() | :not_found
  def get_node(trie) do
    case trie.root_hash do
      <<>> ->
        <<>>

      # node was stored directly
      x when not is_binary(x) ->
        x

      # stored in db
      h ->
        case DB.get(trie.db, h) do
          {:ok, v} -> ExRLP.decode(v)
          :not_found -> :not_found
        end
    end
  end
end
