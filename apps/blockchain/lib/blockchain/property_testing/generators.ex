defmodule Blockchain.PropertyTesting.Generators do
  @moduledoc """
  Property testing generators for blockchain operations.
  
  This module provides StreamData generators for various blockchain
  data structures used in property-based tests.
  """

  import StreamData

  @doc """
  Generates random transaction data.
  """
  def transaction_data do
    map(%{
      nonce: non_negative_integer(),
      gas_price: non_negative_integer(),
      gas_limit: positive_integer(),
      to: binary(length: 20),
      value: non_negative_integer(),
      data: binary()
    })
  end

  @doc """
  Generates random block headers.
  """
  def block_header do
    map(%{
      parent_hash: binary(length: 32),
      ommers_hash: binary(length: 32),
      beneficiary: binary(length: 20),
      state_root: binary(length: 32),
      transactions_root: binary(length: 32),
      receipts_root: binary(length: 32),
      logs_bloom: binary(length: 256),
      difficulty: positive_integer(),
      number: non_negative_integer(),
      gas_limit: positive_integer(),
      gas_used: non_negative_integer(),
      timestamp: positive_integer(),
      extra_data: binary(max_length: 32),
      mix_hash: binary(length: 32),
      nonce: binary(length: 8)
    })
  end

  @doc """
  Generates random addresses (20 bytes).
  """
  def address do
    binary(length: 20)
  end

  @doc """
  Generates random hash values (32 bytes).
  """
  def hash do
    binary(length: 32)
  end

  @doc """
  Generates random private keys (32 bytes).
  """
  def private_key do
    binary(length: 32)
  end

  @doc """
  Generates valid EVM bytecode.
  """
  def evm_bytecode do
    list_of(one_of([
      # PUSH operations
      constant(0x60), # PUSH1
      constant(0x61), # PUSH2
      constant(0x63), # PUSH4
      
      # Stack operations  
      constant(0x80), # DUP1
      constant(0x90), # SWAP1
      constant(0x50), # POP
      
      # Arithmetic
      constant(0x01), # ADD
      constant(0x02), # MUL
      constant(0x03), # SUB
      
      # Storage
      constant(0x54), # SLOAD
      constant(0x55), # SSTORE
      
      # Control flow
      constant(0x00), # STOP
      constant(0xf3)  # RETURN
    ]))
    |> map(&:binary.list_to_bin/1)
  end
end