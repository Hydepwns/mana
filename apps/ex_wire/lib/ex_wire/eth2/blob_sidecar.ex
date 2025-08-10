defmodule ExWire.Eth2.BlobSidecar do
  @moduledoc """
  Blob sidecar for EIP-4844 blob transactions.
  
  Contains the blob data, KZG commitment, and proofs necessary
  for blob verification in the consensus layer.
  """
  
  defstruct [
    :index,
    :blob,
    :kzg_commitment,
    :kzg_proof,
    :signed_block_header,
    :kzg_commitment_inclusion_proof
  ]
  
  @type t :: %__MODULE__{
    index: non_neg_integer(),
    blob: binary(),
    kzg_commitment: binary(),
    kzg_proof: binary(),
    signed_block_header: map(),
    kzg_commitment_inclusion_proof: [binary()]
  }
  
  @doc """
  Validate that a blob sidecar has the correct structure.
  """
  @spec validate_structure(t()) :: :ok | {:error, term()}
  def validate_structure(sidecar) do
    cond do
      not is_integer(sidecar.index) or sidecar.index < 0 ->
        {:error, :invalid_index}
        
      not is_binary(sidecar.blob) ->
        {:error, :invalid_blob}
        
      not is_binary(sidecar.kzg_commitment) ->
        {:error, :invalid_commitment}
        
      not is_binary(sidecar.kzg_proof) ->
        {:error, :invalid_proof}
        
      not is_map(sidecar.signed_block_header) ->
        {:error, :invalid_block_header}
        
      not is_list(sidecar.kzg_commitment_inclusion_proof) ->
        {:error, :invalid_inclusion_proof}
        
      true ->
        :ok
    end
  end
  
  @doc """
  Get the blob size in bytes.
  """
  @spec blob_size(t()) :: non_neg_integer()
  def blob_size(sidecar) do
    byte_size(sidecar.blob)
  end
end