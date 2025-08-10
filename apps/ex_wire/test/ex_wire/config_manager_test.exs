defmodule ExWire.ConfigManagerTest do
  use ExUnit.Case, async: false
  
  alias ExWire.ConfigManager
  alias ExWire.Config.{Validator, Migrator}
  
  setup do
    # Start a fresh ConfigManager for each test
    if pid = Process.whereis(ConfigManager) do
      GenServer.stop(pid)
    end
    
    # Create a test config file
    test_config = """
    blockchain:
      network: mainnet
      chain_id: 1
      eip1559: true
    
    p2p:
      max_peers: 50
      port: 30303
      discovery: true
      protocol_version: 67
      capabilities:
        - eth/66
        - eth/67
    
    sync:
      mode: fast
      checkpoint_sync: true
      parallel_downloads: 10
    
    storage:
      db_path: ./test_db
      pruning: true
      pruning_mode: balanced
      cache_size: 1024
    """
    
    File.write!("test_config.yml", test_config)
    
    {:ok, _pid} = ConfigManager.start_link(config_file: "test_config.yml")
    
    on_exit(fn ->
      File.rm("test_config.yml")
      if pid = Process.whereis(ConfigManager) do
        GenServer.stop(pid)
      end
    end)
    
    :ok
  end
  
  describe "basic configuration operations" do
    test "gets configuration values by path" do
      assert ConfigManager.get([:blockchain, :network]) == "mainnet"
      assert ConfigManager.get([:p2p, :max_peers]) == 50
      assert ConfigManager.get([:sync, :mode]) == "fast"
    end
    
    test "returns default for missing keys" do
      assert ConfigManager.get([:non, :existent], "default") == "default"
    end
    
    test "gets required configuration values" do
      assert ConfigManager.get!([:blockchain, :network]) == "mainnet"
      
      assert_raise RuntimeError, ~r/Required configuration key missing/, fn ->
        ConfigManager.get!([:non, :existent])
      end
    end
    
    test "sets configuration values at runtime" do
      assert ConfigManager.set([:p2p, :max_peers], 100) == :ok
      assert ConfigManager.get([:p2p, :max_peers]) == 100
    end
    
    test "updates multiple values atomically" do
      updates = %{
        [:p2p, :max_peers] => 75,
        [:sync, :mode] => "full",
        [:storage, :cache_size] => 2048
      }
      
      assert ConfigManager.update(updates) == :ok
      assert ConfigManager.get([:p2p, :max_peers]) == 75
      assert ConfigManager.get([:sync, :mode]) == "full"
      assert ConfigManager.get([:storage, :cache_size]) == 2048
    end
  end
  
  describe "environment overrides" do
    test "applies environment-specific configuration" do
      # Create test environment config
      test_env_config = """
      p2p:
        max_peers: 10
        port: 30304
      
      storage:
        db_path: ./test_env_db
      """
      
      File.write!("config/test.yml", test_env_config)
      
      config = ConfigManager.for_environment(:test)
      
      # Environment config should override base config
      assert get_in(config, [:p2p, :max_peers]) == 10
      assert get_in(config, [:p2p, :port]) == 30304
      assert get_in(config, [:storage, :db_path]) == "./test_env_db"
      
      # Other values should remain from base config
      assert get_in(config, [:blockchain, :network]) == "mainnet"
      
      File.rm("config/test.yml")
    end
    
    test "gets current environment" do
      env = ConfigManager.current_environment()
      assert env in [:dev, :test, :prod]
    end
  end
  
  describe "configuration watching" do
    test "registers and triggers watchers on changes" do
      test_pid = self()
      
      {:ok, watcher_id} = ConfigManager.watch([:p2p], fn path, value ->
        send(test_pid, {:config_changed, path, value})
      end)
      
      ConfigManager.set([:p2p, :max_peers], 200)
      
      assert_receive {:config_changed, [:p2p, :max_peers], 200}, 1000
      
      ConfigManager.unwatch(watcher_id)
    end
    
    test "multiple watchers can observe same path" do
      test_pid = self()
      
      {:ok, watcher1} = ConfigManager.watch([:p2p, :max_peers], fn path, value ->
        send(test_pid, {:watcher1, path, value})
      end)
      
      {:ok, watcher2} = ConfigManager.watch([:p2p], fn path, value ->
        send(test_pid, {:watcher2, path, value})
      end)
      
      ConfigManager.set([:p2p, :max_peers], 150)
      
      assert_receive {:watcher1, [:p2p, :max_peers], 150}, 1000
      assert_receive {:watcher2, [:p2p, :max_peers], 150}, 1000
      
      ConfigManager.unwatch(watcher1)
      ConfigManager.unwatch(watcher2)
    end
  end
  
  describe "hot reload" do
    test "reloads configuration from file" do
      # Modify the config file
      updated_config = """
      blockchain:
        network: goerli
        chain_id: 5
        eip1559: true
      
      p2p:
        max_peers: 100
        port: 30303
        discovery: true
        protocol_version: 67
        capabilities:
          - eth/66
          - eth/67
      
      sync:
        mode: warp
        checkpoint_sync: true
        parallel_downloads: 20
      
      storage:
        db_path: ./test_db
        pruning: true
        pruning_mode: aggressive
        cache_size: 2048
      """
      
      File.write!("test_config.yml", updated_config)
      
      # Trigger reload
      ConfigManager.reload()
      
      # Allow time for async reload
      Process.sleep(100)
      
      # Check updated values
      assert ConfigManager.get([:blockchain, :network]) == "goerli"
      assert ConfigManager.get([:blockchain, :chain_id]) == 5
      assert ConfigManager.get([:p2p, :max_peers]) == 100
      assert ConfigManager.get([:sync, :mode]) == "warp"
      assert ConfigManager.get([:storage, :pruning_mode]) == "aggressive"
    end
    
    test "enables and disables auto-reload" do
      assert ConfigManager.set_reload(false) == :ok
      
      # Modify config file
      updated_config = """
      blockchain:
        network: sepolia
        chain_id: 11155111
        eip1559: true
      
      p2p:
        max_peers: 25
        port: 30303
        discovery: true
        protocol_version: 67
        capabilities:
          - eth/66
          - eth/67
      
      sync:
        mode: full
        checkpoint_sync: false
        parallel_downloads: 5
      
      storage:
        db_path: ./test_db
        pruning: false
        pruning_mode: none
        cache_size: 512
      """
      
      File.write!("test_config.yml", updated_config)
      
      # Auto-reload is disabled, so values shouldn't change
      Process.sleep(100)
      assert ConfigManager.get([:blockchain, :network]) == "mainnet"
      
      # Re-enable and trigger
      assert ConfigManager.set_reload(true) == :ok
      ConfigManager.reload()
      Process.sleep(100)
      
      assert ConfigManager.get([:blockchain, :network]) == "sepolia"
    end
  end
  
  describe "validation" do
    test "validates configuration against schema" do
      result = ConfigManager.validate()
      assert result == :ok
    end
    
    test "exports configuration to file" do
      export_path = "exported_config.yml"
      
      assert ConfigManager.export(export_path) == :ok
      assert File.exists?(export_path)
      
      # Read and verify exported config
      {:ok, content} = File.read(export_path)
      {:ok, exported} = YamlElixir.read_from_string(content)
      
      assert exported["blockchain"]["network"] == "mainnet"
      assert exported["p2p"]["max_peers"] == 50
      
      File.rm(export_path)
    end
  end
end