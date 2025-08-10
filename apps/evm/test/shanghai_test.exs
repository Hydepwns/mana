defmodule EVM.ShanghaiTest do
  use ExUnit.Case, async: true
  
  alias EVM.{ExecEnv, MachineState, Configuration}
  alias EVM.Operation.StackMemoryStorageAndFlow
  
  describe "EIP-1153: Transient Storage" do
    setup do
      config = Configuration.Shanghai.new()
      address = 0x0000000000000000000000000000000000000001
      
      exec_env = %ExecEnv{
        address: address,
        transient_storage: %{},
        config: config
      }
      
      machine_state = %MachineState{
        stack: []
      }
      
      {:ok, exec_env: exec_env, machine_state: machine_state}
    end
    
    test "TSTORE and TLOAD basic functionality", %{exec_env: exec_env, machine_state: machine_state} do
      key = 0x1234
      value = 0x5678
      
      # Store value in transient storage
      result = StackMemoryStorageAndFlow.tstore([key, value], %{exec_env: exec_env})
      updated_exec_env = result[:exec_env]
      
      # Load value from transient storage
      result = StackMemoryStorageAndFlow.tload([key], %{
        exec_env: updated_exec_env,
        machine_state: machine_state
      })
      
      assert result[:stack] == [value]
    end
    
    test "TLOAD returns 0 for non-existent key", %{exec_env: exec_env, machine_state: machine_state} do
      key = 0x9999
      
      result = StackMemoryStorageAndFlow.tload([key], %{
        exec_env: exec_env,
        machine_state: machine_state
      })
      
      assert result[:stack] == [0]
    end
    
    test "transient storage is isolated per contract", %{machine_state: machine_state} do
      config = Configuration.Shanghai.new()
      address1 = 0x0000000000000000000000000000000000000001
      address2 = 0x0000000000000000000000000000000000000002
      
      key = 0x1234
      value1 = 0x5678
      value2 = 0x9ABC
      
      # Store in contract 1
      exec_env1 = %ExecEnv{address: address1, transient_storage: %{}, config: config}
      result1 = StackMemoryStorageAndFlow.tstore([key, value1], %{exec_env: exec_env1})
      
      # Store same key in contract 2
      exec_env2 = %ExecEnv{
        address: address2, 
        transient_storage: result1[:exec_env].transient_storage,
        config: config
      }
      result2 = StackMemoryStorageAndFlow.tstore([key, value2], %{exec_env: exec_env2})
      
      # Load from contract 1 (should still be value1)
      exec_env1_updated = %{result1[:exec_env] | transient_storage: result2[:exec_env].transient_storage}
      result_load1 = StackMemoryStorageAndFlow.tload([key], %{
        exec_env: exec_env1_updated,
        machine_state: machine_state
      })
      
      # Load from contract 2 (should be value2)
      result_load2 = StackMemoryStorageAndFlow.tload([key], %{
        exec_env: result2[:exec_env],
        machine_state: machine_state
      })
      
      assert result_load1[:stack] == [value1]
      assert result_load2[:stack] == [value2]
    end
  end
  
  describe "EIP-6780: SELFDESTRUCT changes" do
    setup do
      config = Configuration.Shanghai.new()
      address = 0x0000000000000000000000000000000000000001
      recipient = 0x0000000000000000000000000000000000000002
      
      account_repo = EVM.Mock.MockAccountRepo.new()
      
      exec_env = %ExecEnv{
        address: address,
        account_repo: account_repo,
        config: config,
        created_contracts: MapSet.new()
      }
      
      sub_state = %EVM.SubState{}
      
      {:ok, exec_env: exec_env, sub_state: sub_state, recipient: recipient}
    end
    
    test "SELFDESTRUCT only transfers balance post-Shanghai (not created in same tx)", 
         %{exec_env: exec_env, sub_state: sub_state, recipient: recipient} do
      # Set up account with balance
      account_repo = exec_env.account_repo
      account_repo = EVM.AccountRepo.repo(account_repo).add_account(
        account_repo,
        exec_env.address,
        %{balance: 1000, nonce: 0, storage_root: <<>>, code_hash: <<>>}
      )
      exec_env = %{exec_env | account_repo: account_repo}
      
      # Simulate contract NOT created in same transaction
      result = EVM.Operation.System.selfdestruct([recipient], %{
        exec_env: exec_env,
        sub_state: sub_state
      })
      
      # Should not mark account for destruction
      refute MapSet.member?(result.sub_state.selfdestruct_list, exec_env.address)
    end
    
    test "SELFDESTRUCT fully deletes if created in same transaction",
         %{exec_env: exec_env, sub_state: sub_state, recipient: recipient} do
      # Set up account with balance
      account_repo = exec_env.account_repo
      account_repo = EVM.AccountRepo.repo(account_repo).add_account(
        account_repo,
        exec_env.address,
        %{balance: 1000, nonce: 0, storage_root: <<>>, code_hash: <<>>}
      )
      
      # Simulate contract created in same transaction
      exec_env_with_creation = %{exec_env | 
        account_repo: account_repo,
        created_contracts: MapSet.put(exec_env.created_contracts, exec_env.address)
      }
      
      result = EVM.Operation.System.selfdestruct([recipient], %{
        exec_env: exec_env_with_creation,
        sub_state: sub_state
      })
      
      # Should mark account for destruction
      assert MapSet.member?(result.sub_state.selfdestruct_list, exec_env.address)
    end
    
    test "SELFDESTRUCT behaves traditionally pre-Shanghai",
         %{sub_state: sub_state, recipient: recipient} do
      # Use pre-Shanghai config
      config = Configuration.Constantinople.new()
      address = 0x0000000000000000000000000000000000000001
      account_repo = EVM.Mock.MockAccountRepo.new()
      
      # Set up account with balance
      account_repo = EVM.AccountRepo.repo(account_repo).add_account(
        account_repo,
        address,
        %{balance: 1000, nonce: 0, storage_root: <<>>, code_hash: <<>>}
      )
      
      exec_env = %ExecEnv{
        address: address,
        account_repo: account_repo,
        config: config,
        created_contracts: MapSet.new()
      }
      
      result = EVM.Operation.System.selfdestruct([recipient], %{
        exec_env: exec_env,
        sub_state: sub_state
      })
      
      # Should always mark for destruction pre-Shanghai
      assert MapSet.member?(result.sub_state.selfdestruct_list, exec_env.address)
    end
  end
  
  describe "Shanghai Configuration" do
    test "Shanghai config has required flags" do
      config = Configuration.Shanghai.new()
      
      assert config.has_transient_storage == true
      assert config.has_blob_transactions == true
      assert config.has_beacon_withdrawals == true
      assert config.has_modified_selfdestruct == true
    end
    
    test "transient storage gas costs are configured" do
      config = Configuration.Shanghai.new()
      
      assert config.transient_storage_load_cost == 100
      assert config.transient_storage_store_cost == 100
    end
    
    test "blob transaction parameters are configured" do
      config = Configuration.Shanghai.new()
      
      assert config.blob_gas_per_blob == 131_072
      assert config.target_blob_gas_per_block == 393_216
      assert config.max_blob_gas_per_block == 786_432
      assert config.min_base_fee_per_blob_gas == 1
    end
  end
  
  describe "Blob Base Fee Calculation" do
    test "calculate_blob_base_fee with no excess gas" do
      # When there's no excess gas, base fee should be minimum
      base_fee = Configuration.Shanghai.calculate_blob_base_fee(0, 0)
      assert base_fee == 1
    end
    
    test "calculate_blob_base_fee with excess gas" do
      # When there's excess gas, base fee should increase
      parent_excess = 393_216  # One target worth
      parent_used = 393_216    # One more target worth
      
      base_fee = Configuration.Shanghai.calculate_blob_base_fee(parent_excess, parent_used)
      
      # Fee should be higher than minimum
      assert base_fee > 1
    end
  end
end