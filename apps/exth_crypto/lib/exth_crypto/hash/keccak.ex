defmodule ExthCrypto.Hash.Keccak do
  @moduledoc """
  Simple wrapper for Keccak function for Ethereum.

  Note: This module defines KECCAK as defined by Ethereum, which differs slightly
  than that assigned as the new SHA-3 variant. For SHA-3, a few constants have
  been changed prior to adoption by NIST, but after adoption by Ethereum.

  TODO: Currently using crypto:hash/2 as fallback when keccakf1600 is not available.
  This is not the exact Keccak implementation but provides compatibility for compilation.
  """

  @type keccak_hash :: ExthCrypto.Hash.hash()
  @type keccak_mac :: {atom(), binary()}

  # Check if keccakf1600 is available at compile time
  @keccakf1600_available :erlang.function_exported(:keccakf1600, :sha3_256, 1)

  @doc """
  Returns the keccak sha256 of a given input.

  ## Examples

      iex> ExthCrypto.Hash.Keccak.kec("hello world")
      <<71, 23, 50, 133, 168, 215, 52, 30, 94, 151, 47, 198, 119, 40, 99,
        132, 248, 2, 248, 239, 66, 165, 236, 95, 3, 187, 250, 37, 76, 176,
        31, 173>>

      iex> ExthCrypto.Hash.Keccak.kec(<<0x01, 0x02, 0x03>>)
      <<241, 136, 94, 218, 84, 183, 160, 83, 49, 140, 212, 30, 32, 147, 34,
        13, 171, 21, 214, 83, 129, 177, 21, 122, 54, 51, 168, 59, 253, 92,
        146, 57>>
  """
  @spec kec(binary()) :: keccak_hash
  if @keccakf1600_available do
    def kec(data) do
      :keccakf1600.sha3_256(data)
    end
  else
    def kec(data) do
      # Fallback to crypto:hash/2 for compilation compatibility
      # TODO: This is not the exact Keccak implementation
      :crypto.hash(:sha256, data)
    end
  end

  @doc """
  Returns the keccak sha512 of a given input.

  ## Examples

      iex> ExthCrypto.Hash.Keccak.kec512("hello world")
      <<62, 226, 180, 0, 71, 184, 6, 15, 104, 198, 114, 66, 23, 86, 96, 244, 23, 77,
        10, 245, 192, 29, 71, 22, 142, 194, 14, 214, 25, 176, 183, 196, 33, 129, 244,
        10, 161, 4, 111, 57, 226, 239, 158, 252, 105, 16, 120, 42, 153, 142, 0, 19,
        209, 114, 69, 137, 87, 149, 127, 172, 148, 5, 182, 125>>
  """
  @spec kec512(binary()) :: keccak_hash
  if @keccakf1600_available do
    def kec512(data) do
      :keccakf1600.sha3_512(data)
    end
  else
    def kec512(data) do
      # Fallback to crypto:hash/2 for compilation compatibility
      # TODO: This is not the exact Keccak implementation
      :crypto.hash(:sha512, data)
    end
  end

  @doc """
  Initializes a new Keccak mac stream.

  ## Examples

      iex> keccak_mac = ExthCrypto.Hash.Keccak.init_mac()
      iex> is_nil(keccak_mac)
      false
  """
  @spec init_mac() :: keccak_mac
  if @keccakf1600_available do
    def init_mac() do
      :keccakf1600.init(:sha3_256)
    end
  else
    def init_mac() do
      # Fallback implementation
      {:sha256, <<>>}
    end
  end

  @doc """
  Updates a given Keccak mac stream with the given
  secret and data, returning a new mac stream.

  ## Examples

      iex> keccak_mac = ExthCrypto.Hash.Keccak.init_mac()
      ...> |> ExthCrypto.Hash.Keccak.update_mac("data")
      iex> is_nil(keccak_mac)
      false
  """
  @spec update_mac(keccak_mac, binary()) :: keccak_mac
  if @keccakf1600_available do
    def update_mac(mac, data) do
      :keccakf1600.update(mac, data)
    end
  else
    def update_mac(mac, data) do
      # Fallback implementation - accumulate data
      case mac do
        {:sha256, acc} -> {:sha256, acc <> data}
        {:sha512, acc} -> {:sha512, acc <> data}
      end
    end
  end

  @doc """
  Finalizes a given Keccak mac stream to produce the current hash.

  ## Examples

      iex> ExthCrypto.Hash.Keccak.init_mac()
      ...> |> ExthCrypto.Hash.Keccak.update_mac("data")
      ...> |> ExthCrypto.Hash.Keccak.final_mac()
      ...> |> ExthCrypto.Math.bin_to_hex
      "8f54f1c2d0eb5771cd5bf67a6689fcd6eed9444d91a39e5ef32a9b4ae5ca14ff"
  """
  @spec final_mac(keccak_mac) :: keccak_hash
  if @keccakf1600_available do
    def final_mac(mac) do
      :keccakf1600.final(mac)
    end
  else
    def final_mac(mac) do
      # Fallback implementation - hash accumulated data
      case mac do
        {:sha256, data} -> :crypto.hash(:sha256, data)
        {:sha512, data} -> :crypto.hash(:sha512, data)
      end
    end
  end
end
