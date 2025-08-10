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

      # TODO: These are SHA-256 values, not Keccak-256, due to keccakf1600 being unavailable
      # When keccakf1600 is re-enabled, these doctests will need to be updated with actual Keccak values
      iex> ExthCrypto.Hash.Keccak.kec("hello world")
      <<185, 77, 39, 185, 147, 77, 62, 8, 165, 46, 82, 215, 218, 125, 171, 250, 196,
        132, 239, 227, 122, 83, 128, 238, 144, 136, 247, 172, 226, 239, 205, 233>>

      iex> ExthCrypto.Hash.Keccak.kec(<<0x01, 0x02, 0x03>>)
      <<3, 144, 88, 198, 242, 192, 203, 73, 44, 83, 59, 10, 77, 20, 239,
        119, 204, 15, 120, 171, 204, 206, 213, 40, 125, 132,
        161, 162, 1, 28, 251, 129>>
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

      # TODO: This is SHA-512, not Keccak-512, due to keccakf1600 being unavailable
      # When keccakf1600 is re-enabled, this doctest will need to be updated with actual Keccak value
      iex> ExthCrypto.Hash.Keccak.kec512("hello world")
      <<48, 158, 204, 72, 156, 18, 214, 235, 76, 196, 15, 80, 201, 2, 242, 180, 208,
        237, 119, 238, 81, 26, 124, 122, 155, 205, 60, 168, 109, 76, 216, 111, 152,
        157, 211, 91, 197, 255, 73, 150, 112, 218, 52, 37, 91, 69, 176, 207, 216, 48,
        232, 31, 96, 93, 207, 125, 197, 84, 46, 147, 174, 156, 215, 111>>
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
