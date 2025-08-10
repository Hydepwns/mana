defmodule EVM do
  @moduledoc """
  Documentation for EVM.
  """

  # σ[a]
  @type account :: %{
          # σ[a]_n
          nonce: integer(),
          # σ[a]_b
          balance: integer(),
          # σ[a]_s
          storage: MerklePatriciaTree.Trie.t(),
          # σ[a]_c
          code: binary()
        }
  # σ
  @type state :: %{address() => account()}
  @type trie_root :: MerklePatriciaTree.Trie.root_hash()
  @type val :: integer()
  @type address :: <<_::160>>
  @type hash :: <<_::256>>
  @type timestamp :: integer()

  @word_size_in_bytes 4
  @byte_size 8
  @int_size 256
  @max_int round(:math.pow(2, @int_size))

  @doc """
  Returns maximum allowed integer size.
  """
  def max_int(), do: @max_int
  def int_size(), do: @int_size
  def byte_size(), do: @byte_size

  @doc """
  Returns word size in bits.
  """
  def word_size(), do: @word_size_in_bytes * @byte_size
end
