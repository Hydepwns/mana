defmodule ExWire.Eth2.PruningMetricsTest do
  use ExUnit.Case, async: false
  
  alias ExWire.Eth2.PruningMetrics
  
  @moduletag :metrics
  
  setup do
    # Start metrics server for testing
    {:ok, _pid} = PruningMetrics.start_link(name: :"#{__MODULE__}_metrics")
    
    on_exit(fn ->
      # Clean up ETS tables
      for table <- [:pruning_operations, :space_tracking, :performance_samples, :system_impact_log, :tier_migrations] do
        if :ets.info(table) != :undefined do
          :ets.delete_all_objects(table)
        end
      end
    end)
    
    %{metrics_server: :"#{__MODULE__}_metrics"}
  end
  
  describe "operation metrics recording" do
    test "records successful operation metrics", %{metrics_server: server} do
      # Record a successful pruning operation
      PruningMetrics.record_operation(:fork_choice, :ok, 5000, %{pruned_blocks: 100})
      
      # Allow some time for async processing
      Process.sleep(100)
      
      # Get metrics summary
      {:ok, summary} = GenServer.call(server, :get_metrics_summary)
      
      # Verify operation was recorded
      assert summary.operations.total_operations >= 1
      assert summary.operations.successful_operations >= 1
      assert summary.operations.success_rate > 0
    end
    
    test "records failed operation metrics", %{metrics_server: server} do
      # Record a failed pruning operation
      PruningMetrics.record_operation(:states, :error, 2000, %{error: :timeout})
      
      Process.sleep(100)
      
      {:ok, summary} = GenServer.call(server, :get_metrics_summary)
      
      # Verify failure was recorded
      assert summary.operations.total_operations >= 1
      assert summary.operations.failed_operations >= 1
      assert summary.operations.success_rate < 100
    end
    
    test "tracks operation duration correctly" do
      # Record operations with different durations
      PruningMetrics.record_operation(:attestations, :ok, 1000, %{})
      PruningMetrics.record_operation(:attestations, :ok, 3000, %{})
      PruningMetrics.record_operation(:attestations, :ok, 2000, %{})
      
      Process.sleep(100)
      
      {:ok, summary} = GenServer.call(:"#{__MODULE__}_metrics", :get_metrics_summary)
      
      # Average should be 2000ms
      assert summary.operations.avg_duration_ms == 2000.0
    end
  end
  
  describe "space tracking" do
    test "records space freed by different data types" do
      # Record space freed by different pruning strategies
      PruningMetrics.record_space_freed(:fork_choice, 50.5, 100.0, 49.5)
      PruningMetrics.record_space_freed(:states, 125.0, 200.0, 75.0)
      PruningMetrics.record_space_freed(:attestations, 10.2, 25.0, 14.8)
      
      Process.sleep(100)
      
      {:ok, summary} = GenServer.call(:"#{__MODULE__}_metrics", :get_metrics_summary)
      
      # Verify total space savings
      total_expected = 50.5 + 125.0 + 10.2
      assert_in_delta(summary.space_savings.total_space_freed_mb, total_expected, 0.1)
    end
    
    test "calculates pruning efficiency correctly" do
      # Record operations with known efficiency
      PruningMetrics.record_operation(:states, :ok, 10000, %{})  # 10 seconds
      PruningMetrics.record_space_freed(:states, 100.0, 100.0, 0.0)  # 100 MB freed
      
      Process.sleep(100)
      
      {:ok, analysis} = GenServer.call(:"#{__MODULE__}_metrics", :get_efficiency_analysis)
      
      # Should be 10 MB/s efficiency (100 MB in 10 seconds)
      strategy_efficiency = Enum.find(analysis.strategy_efficiency, &(&1.strategy == :states))
      assert strategy_efficiency != nil
      assert strategy_efficiency.efficiency_mb_per_sec == 10.0
    end
  end
  
  describe "system impact tracking" do
    test "records system performance impact" do
      # Record system impact during pruning
      PruningMetrics.record_system_impact(25.5, 1500, 15.0, 250)
      
      Process.sleep(100)
      
      {:ok, summary} = GenServer.call(:"#{__MODULE__}_metrics", :get_metrics_summary)
      
      # Verify impact metrics
      assert summary.system_impact.avg_cpu_usage_percent == 25.5
      assert summary.system_impact.avg_memory_usage_mb == 1500.0
      assert summary.system_impact.avg_io_wait_percent == 15.0
      assert summary.system_impact.avg_consensus_latency_ms == 250.0
    end
    
    test "calculates moving averages correctly" do
      # Record multiple impact samples
      PruningMetrics.record_system_impact(20.0, 1000, 10.0, 200)
      PruningMetrics.record_system_impact(30.0, 2000, 20.0, 300)
      PruningMetrics.record_system_impact(10.0, 500, 5.0, 100)
      
      Process.sleep(100)
      
      {:ok, summary} = GenServer.call(:"#{__MODULE__}_metrics", :get_metrics_summary)
      
      # Should calculate averages: CPU=20%, Memory=1166MB, IO=11.67%, Latency=200ms
      assert_in_delta(summary.system_impact.avg_cpu_usage_percent, 20.0, 0.1)
      assert_in_delta(summary.system_impact.avg_memory_usage_mb, 1166.67, 1.0)
      assert_in_delta(summary.system_impact.avg_io_wait_percent, 11.67, 0.1)
      assert_in_delta(summary.system_impact.avg_consensus_latency_ms, 200.0, 0.1)
    end
  end
  
  describe "storage tier tracking" do
    test "records tier migration statistics" do
      # Record migrations between storage tiers
      PruningMetrics.record_tier_migration(:hot, :warm, 500, 250.0)
      PruningMetrics.record_tier_migration(:warm, :cold, 1000, 500.0)
      
      Process.sleep(100)
      
      {:ok, summary} = GenServer.call(:"#{__MODULE__}_metrics", :get_metrics_summary)
      
      # Verify migration tracking
      assert summary.storage_tiers.hot_to_warm_migrations >= 1
      assert summary.storage_tiers.warm_to_cold_migrations >= 1
      assert summary.storage_tiers.total_data_migrated_mb >= 750.0
    end
  end
  
  describe "efficiency analysis" do
    test "analyzes pruning efficiency across strategies" do
      # Set up test data for different strategies
      strategies = [:fork_choice, :states, :attestations, :blocks]
      
      Enum.each(strategies, fn strategy ->
        # Record operation with different efficiencies
        duration = case strategy do
          :fork_choice -> 5000    # 5s -> 20 MB/s
          :states -> 10000        # 10s -> 10 MB/s  
          :attestations -> 2000   # 2s -> 50 MB/s
          :blocks -> 20000        # 20s -> 5 MB/s
        end
        
        PruningMetrics.record_operation(strategy, :ok, duration, %{})
        PruningMetrics.record_space_freed(strategy, 100.0, 100.0, 0.0)
      end)
      
      Process.sleep(100)
      
      {:ok, analysis} = GenServer.call(:"#{__MODULE__}_metrics", :get_efficiency_analysis)
      
      # Verify efficiency ranking (attestations should be most efficient)
      assert analysis.most_efficient_strategy == :attestations
      assert analysis.least_efficient_strategy == :blocks
      
      # Find attestation strategy efficiency
      att_efficiency = Enum.find(analysis.strategy_efficiency, &(&1.strategy == :attestations))
      assert att_efficiency.efficiency_mb_per_sec == 50.0
    end
  end
  
  describe "storage reporting" do
    test "generates comprehensive storage report" do
      # Record some tier migrations to populate data
      PruningMetrics.record_tier_migration(:hot, :warm, 100, 50.0)
      PruningMetrics.record_tier_migration(:warm, :cold, 200, 100.0)
      
      Process.sleep(100)
      
      {:ok, report} = GenServer.call(:"#{__MODULE__}_metrics", :get_storage_report)
      
      # Verify report structure
      assert Map.has_key?(report, :tier_utilization)
      assert Map.has_key?(report, :migration_statistics)
      assert Map.has_key?(report, :storage_trends)
      assert Map.has_key?(report, :optimization_opportunities)
      
      # Check tier utilization data
      assert Map.has_key?(report.tier_utilization, :hot_storage)
      assert Map.has_key?(report.tier_utilization, :warm_storage)
      assert Map.has_key?(report.tier_utilization, :cold_storage)
    end
  end
  
  describe "optimization recommendations" do
    test "generates recommendations for poor performance" do
      # Simulate poor performance scenario
      PruningMetrics.record_operation(:states, :ok, 60000, %{})  # Very slow: 60s
      PruningMetrics.record_space_freed(:states, 10.0, 10.0, 0.0)  # Low efficiency: 0.17 MB/s
      PruningMetrics.record_system_impact(90.0, 3000, 50.0, 1000)  # High system impact
      
      Process.sleep(100)
      
      {:ok, recommendations} = GenServer.call(:"#{__MODULE__}_metrics", :get_recommendations)
      
      # Should generate multiple recommendations for poor performance
      assert length(recommendations.recommendations) > 0
      assert recommendations.overall_health_score < 100
      
      # Check for specific recommendation types
      rec_types = Enum.map(recommendations.recommendations, & &1.type)
      assert :performance in rec_types or :system_impact in rec_types
    end
    
    test "provides good health score for optimal performance" do
      # Simulate good performance scenario
      PruningMetrics.record_operation(:states, :ok, 5000, %{})   # Fast: 5s
      PruningMetrics.record_space_freed(:states, 100.0, 100.0, 0.0)  # Good efficiency: 20 MB/s
      PruningMetrics.record_system_impact(10.0, 500, 5.0, 100)   # Low system impact
      
      Process.sleep(100)
      
      {:ok, recommendations} = GenServer.call(:"#{__MODULE__}_metrics", :get_recommendations)
      
      # Should have high health score with few recommendations
      assert recommendations.overall_health_score >= 80
    end
  end
  
  describe "metrics export" do
    test "exports metrics data in JSON format" do
      # Record some test data
      PruningMetrics.record_operation(:fork_choice, :ok, 1000, %{})
      PruningMetrics.record_space_freed(:fork_choice, 25.0, 25.0, 0.0)
      
      Process.sleep(100)
      
      # Get dashboard data and export
      {:ok, dashboard_data} = GenServer.call(:"#{__MODULE__}_metrics", :get_dashboard_data)
      
      # Should be able to encode as JSON (basic validation)
      assert is_map(dashboard_data)
    end
  end
  
  describe "time-based metrics" do
    test "tracks daily space savings" do
      # Record space freed on specific day
      PruningMetrics.record_space_freed(:states, 100.0, 100.0, 0.0)
      PruningMetrics.record_space_freed(:attestations, 50.0, 50.0, 0.0)
      
      Process.sleep(100)
      
      {:ok, summary} = GenServer.call(:"#{__MODULE__}_metrics", :get_metrics_summary)
      
      # Should track today's savings
      assert summary.space_savings.space_freed_today_mb >= 150.0
    end
  end
  
  describe "error handling" do
    test "handles concurrent metric recording safely" do
      # Spawn multiple processes recording metrics concurrently
      tasks = for i <- 1..20 do
        Task.async(fn ->
          PruningMetrics.record_operation(:states, :ok, i * 100, %{task_id: i})
          PruningMetrics.record_space_freed(:states, i * 5.0, i * 10.0, i * 5.0)
        end)
      end
      
      # Wait for all tasks to complete
      Task.await_many(tasks, 5000)
      
      Process.sleep(200)
      
      # Verify all operations were recorded
      {:ok, summary} = GenServer.call(:"#{__MODULE__}_metrics", :get_metrics_summary)
      assert summary.operations.total_operations >= 20
    end
    
    test "recovers gracefully from invalid data" do
      # Try to record invalid metrics
      assert :ok = PruningMetrics.record_operation(:invalid_type, :ok, 1000, %{})
      assert :ok = PruningMetrics.record_space_freed(:invalid_type, -100.0, 0.0, 100.0)  # Negative space freed
      
      Process.sleep(100)
      
      # Metrics server should still be responsive
      {:ok, _summary} = GenServer.call(:"#{__MODULE__}_metrics", :get_metrics_summary)
    end
  end
end