defmodule EVM.Configuration.Shanghai do
  @moduledoc """
  Shanghai hardfork configuration.
  
  Includes support for:
  - EIP-1153: Transient storage opcodes (TSTORE/TLOAD)
  - EIP-4895: Beacon chain withdrawal operations
  - EIP-6780: SELFDESTRUCT changes
  - EIP-4844: Blob transactions (proto-danksharding)
  """
  
  alias EVM.Configuration.Constantinople

  use EVM.Configuration,
    fallback_config: Constantinople,
    overrides: %{
      has_transient_storage: true,
      has_blob_transactions: true,
      has_beacon_withdrawals: true,
      has_modified_selfdestruct: true,
      # Gas costs for transient storage
      transient_storage_load_cost: 100,
      transient_storage_store_cost: 100,
      # Blob transaction constants
      blob_gas_per_blob: 131_072,  # 2^17
      target_blob_gas_per_block: 393_216,  # 3 * 2^17
      max_blob_gas_per_block: 786_432,  # 6 * 2^17
      min_base_fee_per_blob_gas: 1,
      blob_base_fee_update_fraction: 3_338_477,
      # Version hash for KZG commitments
      versioned_hash_version_kzg: 0x01
    }

  @impl true
  def selfdestruct_cost(config, params) do
    # Shanghai modifies SELFDESTRUCT behavior but keeps same gas cost
    Constantinople.selfdestruct_cost(config, params)
  end

  @impl true
  def limit_contract_code_size?(config, size) do
    Constantinople.limit_contract_code_size?(config, size)
  end

  @doc """
  Calculate blob base fee from header.
  Uses fake exponential formula from EIP-4844.
  """
  def calculate_blob_base_fee(parent_excess_blob_gas, parent_blob_gas_used) do
    excess_blob_gas = calculate_excess_blob_gas(parent_excess_blob_gas, parent_blob_gas_used)
    fake_exponential(
      config(:min_base_fee_per_blob_gas),
      excess_blob_gas,
      config(:blob_base_fee_update_fraction)
    )
  end
  
  defp calculate_excess_blob_gas(parent_excess_blob_gas, parent_blob_gas_used) do
    target = config(:target_blob_gas_per_block)
    excess = parent_excess_blob_gas + parent_blob_gas_used
    
    if excess > target do
      excess - target
    else
      0
    end
  end
  
  defp fake_exponential(factor, numerator, denominator) do
    # Returns factor * e^(numerator/denominator) as per EIP-4844
    if numerator == 0 do
      factor
    else
      fake_exponential_loop(factor, numerator, denominator, factor * denominator)
    end
  end
  
  defp fake_exponential_loop(output, 0, _denominator, _numerator_accumulator), do: output
  
  defp fake_exponential_loop(output, i, denominator, numerator_accumulator) do
    output = output + div(numerator_accumulator, denominator)
    numerator_accumulator = div(numerator_accumulator * (i - 1), i)
    
    if numerator_accumulator == 0 do
      output
    else
      fake_exponential_loop(output, i - 1, denominator, numerator_accumulator)
    end
  end
  
  defp config(key) do
    Map.get(__MODULE__.new(), key)
  end
end