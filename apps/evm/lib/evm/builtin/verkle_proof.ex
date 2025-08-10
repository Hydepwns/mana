defmodule EVM.Builtin.VerkleProof do
  @moduledoc """
  Verkle proof verification precompile (EIP-7545).
  
  This precompile allows smart contracts to verify verkle proofs,
  enabling stateless execution and light client implementations.
  
  Address: 0x00000000000000000000000000000000000000021 (tentative)
  
  ## Input Format
  
  The input data is structured as:
  - [32 bytes] Root commitment
  - [32 bytes] Proof size (n)
  - [n bytes] Proof data
  - [32 bytes] Number of key-value pairs (m)
  - For each key-value pair:
    - [32 bytes] Key
    - [32 bytes] Value length (v)
    - [v bytes] Value data
  
  ## Output
  
  - [32 bytes] 0x0000...0001 if proof is valid
  - [32 bytes] 0x0000...0000 if proof is invalid
  
  ## Gas Cost
  
  Base cost: 3000
  Per key-value pair: 200
  Per 32 bytes of proof: 100
  """
  
  alias VerkleTree.Witness
  alias VerkleTree.Crypto
  
  require Logger
  
  # EIP-7545 tentative address for verkle proof verification
  @precompile_address 0x21
  
  # Gas costs (tentative, subject to change)
  @base_gas_cost 3000
  @per_key_value_gas 200
  @per_proof_chunk_gas 100
  @proof_chunk_size 32
  
  @type gas :: non_neg_integer()
  @type exec_env :: EVM.ExecEnv.t()
  @type output :: EVM.VM.output()
  
  @doc """
  Executes the verkle proof verification precompile.
  
  ## Parameters
  
  - `gas` - Available gas
  - `exec_env` - Execution environment containing input data
  
  ## Returns
  
  A tuple containing:
  - Remaining gas
  - Sub-state (empty for precompiles)
  - Updated execution environment
  - Output (verification result)
  """
  @spec exec(gas(), exec_env()) :: {gas(), EVM.SubState.t(), exec_env(), output()}
  def exec(gas, exec_env) do
    input = Map.get(exec_env, :data, <<>>)
    
    case parse_input(input) do
      {:ok, root, proof, key_value_pairs} ->
        gas_cost = calculate_gas_cost(proof, key_value_pairs)
        
        if gas >= gas_cost do
          result = verify_proof(root, proof, key_value_pairs)
          output = encode_result(result)
          
          {gas - gas_cost, %EVM.SubState{}, exec_env, output}
        else
          # Out of gas
          {:error, %EVM.SubState{}, exec_env, :failed}
        end
        
      {:error, _reason} ->
        # Invalid input format
        {gas, %EVM.SubState{}, exec_env, <<0::256>>}
    end
  rescue
    e ->
      Logger.error("Verkle proof verification failed: #{Exception.message(e)}")
      {gas, %EVM.SubState{}, exec_env, <<0::256>>}
  end
  
  @doc """
  Returns the address of this precompile.
  """
  @spec address() :: non_neg_integer()
  def address(), do: @precompile_address
  
  # Private functions
  
  defp parse_input(<<
    root::binary-size(32),
    proof_size::256,
    rest::binary
  >>) when byte_size(rest) >= proof_size do
    <<proof::binary-size(proof_size), kvs_data::binary>> = rest
    
    case parse_key_value_pairs(kvs_data) do
      {:ok, key_value_pairs} ->
        {:ok, root, proof, key_value_pairs}
        
      error ->
        error
    end
  end
  
  defp parse_input(_), do: {:error, :invalid_format}
  
  defp parse_key_value_pairs(<<
    num_pairs::256,
    rest::binary
  >>) do
    parse_kvs(rest, num_pairs, [])
  end
  
  defp parse_key_value_pairs(_), do: {:error, :invalid_kvs}
  
  defp parse_kvs(<<>>, 0, acc), do: {:ok, Enum.reverse(acc)}
  
  defp parse_kvs(<<
    key::binary-size(32),
    value_length::256,
    rest::binary
  >>, remaining, acc) when remaining > 0 and byte_size(rest) >= value_length do
    <<value::binary-size(value_length), next::binary>> = rest
    parse_kvs(next, remaining - 1, [{key, value} | acc])
  end
  
  defp parse_kvs(_, _, _), do: {:error, :invalid_kvs}
  
  defp calculate_gas_cost(proof, key_value_pairs) do
    proof_chunks = div(byte_size(proof) + @proof_chunk_size - 1, @proof_chunk_size)
    kvs_count = length(key_value_pairs)
    
    @base_gas_cost + (proof_chunks * @per_proof_chunk_gas) + (kvs_count * @per_key_value_gas)
  end
  
  defp verify_proof(root, proof_data, key_value_pairs) do
    try do
      # Create witness structure from proof data
      witness = %{data: proof_data, proof: proof_data}
      
      # Verify the proof against the root and key-value pairs
      Witness.verify(witness, root, key_value_pairs)
    rescue
      _ -> false
    end
  end
  
  defp encode_result(true), do: <<1::256>>
  defp encode_result(false), do: <<0::256>>
  
  @doc """
  Checks if the given address corresponds to the verkle proof precompile.
  """
  @spec is_verkle_proof_precompile?(non_neg_integer()) :: boolean()
  def is_verkle_proof_precompile?(address) do
    address == @precompile_address
  end
  
  @doc """
  Returns the minimum gas cost for calling this precompile.
  """
  @spec min_gas_cost() :: non_neg_integer()
  def min_gas_cost(), do: @base_gas_cost
end