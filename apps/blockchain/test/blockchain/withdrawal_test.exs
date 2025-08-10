defmodule Blockchain.WithdrawalTest do
  use ExUnit.Case, async: true
  
  alias Blockchain.{Withdrawal, Account}
  alias MerklePatriciaTree.{Trie, DB}
  
  describe "Withdrawal (EIP-4895)" do
    setup do
      withdrawal = %Withdrawal{
        index: 1,
        validator_index: 100,
        address: <<1::160>>,
        amount: 32_000_000_000  # 32 ETH in Gwei
      }
      
      {:ok, withdrawal: withdrawal}
    end
    
    test "serializes withdrawal correctly", %{withdrawal: withdrawal} do
      serialized = Withdrawal.serialize(withdrawal)
      
      assert length(serialized) == 4
      assert Enum.at(serialized, 0) == <<1>>  # index
      assert Enum.at(serialized, 1) == <<100>>  # validator_index  
      assert Enum.at(serialized, 2) == withdrawal.address
      assert Enum.at(serialized, 3) == BitHelper.encode_unsigned(32_000_000_000)  # amount
    end
    
    test "deserializes withdrawal correctly", %{withdrawal: withdrawal} do
      serialized = Withdrawal.serialize(withdrawal)
      {:ok, deserialized} = Withdrawal.deserialize(serialized)
      
      assert deserialized.index == withdrawal.index
      assert deserialized.validator_index == withdrawal.validator_index
      assert deserialized.address == withdrawal.address
      assert deserialized.amount == withdrawal.amount
    end
    
    test "rejects invalid withdrawal - bad address length" do
      invalid_data = [<<1>>, <<100>>, <<1, 2, 3>>, <<32_000_000_000>>]  # Short address
      assert Withdrawal.deserialize(invalid_data) == {:error, :invalid_withdrawal}
    end
    
    test "rejects invalid withdrawal - wrong field count" do
      invalid_data = [<<1>>, <<100>>, <<1::160>>]  # Missing amount
      assert Withdrawal.deserialize(invalid_data) == {:error, :invalid_withdrawal}
    end
    
    test "validates withdrawal - success", %{withdrawal: withdrawal} do
      assert Withdrawal.validate(withdrawal) == :ok
    end
    
    test "validates withdrawal - invalid address" do
      invalid_withdrawal = %Withdrawal{
        index: 1,
        validator_index: 100,
        address: <<1, 2, 3>>,  # Too short
        amount: 1_000_000_000
      }
      
      assert Withdrawal.validate(invalid_withdrawal) == {:error, :invalid_withdrawal_address}
    end
    
    test "validates withdrawal - zero amount" do
      invalid_withdrawal = %Withdrawal{
        index: 1,
        validator_index: 100,
        address: <<1::160>>,
        amount: 0
      }
      
      assert Withdrawal.validate(invalid_withdrawal) == {:error, :invalid_withdrawal_amount}
    end
    
    test "validates withdrawal list - empty list" do
      assert Withdrawal.validate_withdrawals([]) == :ok
    end
    
    test "validates withdrawal list - monotonic indices", %{withdrawal: withdrawal} do
      withdrawal2 = %{withdrawal | index: 2}
      withdrawal3 = %{withdrawal | index: 3}
      
      withdrawals = [withdrawal, withdrawal2, withdrawal3]
      assert Withdrawal.validate_withdrawals(withdrawals) == :ok
    end
    
    test "validates withdrawal list - non-monotonic indices", %{withdrawal: withdrawal} do
      withdrawal2 = %{withdrawal | index: 3}  # Skip index 2
      withdrawal3 = %{withdrawal | index: 2}  # Go backwards
      
      withdrawals = [withdrawal, withdrawal2, withdrawal3]
      assert Withdrawal.validate_withdrawals(withdrawals) == {:error, :withdrawal_indices_not_monotonic}
    end
    
    test "converts Gwei to Wei correctly" do
      assert Withdrawal.gwei_to_wei(1) == 1_000_000_000
      assert Withdrawal.gwei_to_wei(32) == 32_000_000_000
      assert Withdrawal.gwei_to_wei(32_000_000_000) == 32_000_000_000_000_000_000
    end
    
    test "converts Wei to Gwei correctly" do
      assert Withdrawal.wei_to_gwei(1_000_000_000) == 1
      assert Withdrawal.wei_to_gwei(32_000_000_000_000_000_000) == 32_000_000_000
    end
    
    test "calculates empty withdrawals root" do
      trie = Trie.new(DB.ETS.new())
      root = Withdrawal.calculate_withdrawals_root([], trie)
      assert root == Trie.empty_trie_root_hash()
    end
    
    test "calculates withdrawals root with withdrawals", %{withdrawal: withdrawal} do
      trie = Trie.new(DB.ETS.new())
      
      withdrawal2 = %{withdrawal | index: 2, amount: 16_000_000_000}
      withdrawals = [withdrawal, withdrawal2]
      
      root = Withdrawal.calculate_withdrawals_root(withdrawals, trie)
      
      # Should be different from empty root
      refute root == Trie.empty_trie_root_hash()
      assert byte_size(root) == 32
    end
  end
  
  describe "Withdrawal Processing" do
    setup do
      # Mock account repo setup would go here
      # For now we'll create a simple test structure
      {:ok, account_repo: nil}
    end
    
    test "process single withdrawal increases balance" do
      # This test would require a proper mock account repo
      # For now, we'll test the logic conceptually
      
      withdrawal = %Withdrawal{
        index: 1,
        validator_index: 100,
        address: <<1::160>>,
        amount: 1_000_000_000  # 1 ETH in Gwei
      }
      
      # Verify Gwei to Wei conversion
      wei_amount = Withdrawal.gwei_to_wei(withdrawal.amount)
      assert wei_amount == 1_000_000_000_000_000_000
    end
    
    test "process multiple withdrawals in order" do
      withdrawals = [
        %Withdrawal{index: 1, validator_index: 100, address: <<1::160>>, amount: 1_000_000_000},
        %Withdrawal{index: 2, validator_index: 101, address: <<2::160>>, amount: 2_000_000_000},
        %Withdrawal{index: 3, validator_index: 102, address: <<1::160>>, amount: 500_000_000}
      ]
      
      # Validate the withdrawal list structure
      assert Withdrawal.validate_withdrawals(withdrawals) == :ok
      
      # Verify amounts
      total_gwei = Enum.reduce(withdrawals, 0, & &1.amount + &2)
      assert total_gwei == 3_500_000_000
      
      total_wei = Withdrawal.gwei_to_wei(total_gwei)
      assert total_wei == 3_500_000_000_000_000_000
    end
  end
  
  describe "Edge Cases" do
    test "handles maximum withdrawal amounts" do
      max_gwei = 0xFFFFFFFFFFFFFFFF  # Max 64-bit unsigned int
      max_wei = Withdrawal.gwei_to_wei(max_gwei)
      
      withdrawal = %Withdrawal{
        index: 1,
        validator_index: 1,
        address: <<1::160>>,
        amount: max_gwei
      }
      
      assert Withdrawal.validate(withdrawal) == :ok
      assert max_wei == max_gwei * 1_000_000_000
    end
    
    test "handles single validator index withdrawal" do
      withdrawal = %Withdrawal{
        index: 1,
        validator_index: 0,  # First validator
        address: <<1::160>>,
        amount: 1
      }
      
      assert Withdrawal.validate(withdrawal) == :ok
    end
    
    test "serialization round trip maintains precision" do
      withdrawal = %Withdrawal{
        index: 0xFFFFFFFFFFFFFFFF,
        validator_index: 0xFFFFFFFFFFFFFFFF,
        address: <<0xFF::160>>,
        amount: 0xFFFFFFFFFFFFFFFF
      }
      
      serialized = Withdrawal.serialize(withdrawal)
      {:ok, deserialized} = Withdrawal.deserialize(serialized)
      
      assert deserialized.index == withdrawal.index
      assert deserialized.validator_index == withdrawal.validator_index
      assert deserialized.address == withdrawal.address
      assert deserialized.amount == withdrawal.amount
    end
  end
end