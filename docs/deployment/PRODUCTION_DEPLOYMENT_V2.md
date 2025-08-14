# V2 Production Deployment Guide

## Overview
This document provides comprehensive guidance for deploying V2 modules to production with zero downtime and maximum reliability.

## Pre-Deployment Checklist

### ✅ Code Quality Requirements
- [ ] All V2 modules pass 95%+ test coverage
- [ ] Performance benchmarks show improvement over V1
- [ ] Memory usage profiling completed
- [ ] Security audit passed
- [ ] Documentation updated

### ✅ Infrastructure Requirements
- [ ] Monitoring and alerting configured
- [ ] Rollback mechanisms tested
- [ ] Feature flags implemented
- [ ] Load balancer configuration updated
- [ ] Database migration scripts prepared

### ✅ Testing Requirements
- [ ] Unit tests: 95%+ coverage
- [ ] Integration tests: All critical paths tested
- [ ] Load tests: Performance under expected traffic
- [ ] Chaos tests: Behavior during failures
- [ ] Canary tests: Small-scale production validation

## Deployment Architecture

### Module Routing Strategy
```elixir
# apps/mana/lib/mana/module_router.ex
defmodule Mana.ModuleRouter do
  @moduledoc """
  Routes requests to V1 or V2 modules based on configuration and feature flags.
  Enables zero-downtime migration and instant rollback capabilities.
  """
  
  @behaviour Mana.ModuleRouter.Behaviour
  
  # Feature flag configuration
  def route_module(module_type, request) do
    case {get_version(module_type), get_traffic_split(module_type)} do
      {"v2", traffic_percentage} when traffic_percentage >= random_percentage() ->
        route_to_v2(module_type, request)
      _ ->
        route_to_v1(module_type, request)
    end
  rescue
    error ->
      Logger.error("Module routing error: #{inspect(error)}")
      # Always fallback to V1 on errors
      route_to_v1(module_type, request)
  end
  
  defp get_version(module_type) do
    :mana
    |> Application.get_env(:module_versions, %{})
    |> Map.get(module_type, "v1")
  end
  
  defp get_traffic_split(module_type) do
    :mana
    |> Application.get_env(:traffic_splits, %{})
    |> Map.get(module_type, 0)
  end
  
  defp random_percentage, do: :rand.uniform(100)
  
  # V1 routing
  defp route_to_v1(:transaction_pool, request) do
    Blockchain.TransactionPool.handle_request(request)
  end
  
  defp route_to_v1(:sync_service, request) do
    ExWire.Sync.handle_request(request)
  end
  
  # V2 routing  
  defp route_to_v2(:transaction_pool, request) do
    Blockchain.SimplePoolV2.handle_request(request)
  end
  
  defp route_to_v2(:sync_service, request) do
    ExWire.SimpleSyncV2.handle_request(request)
  end
end
```

### Configuration Management
```elixir
# config/runtime.exs
import Config

# Environment-specific V2 rollout configuration
config :mana,
  module_versions: %{
    transaction_pool: System.get_env("TRANSACTION_POOL_VERSION", "v1"),
    sync_service: System.get_env("SYNC_SERVICE_VERSION", "v1"),
    filter_manager: System.get_env("FILTER_MANAGER_VERSION", "v1"),
    subscription_manager: System.get_env("SUBSCRIPTION_MANAGER_VERSION", "v1")
  }

# Traffic splitting for gradual rollout
config :mana,
  traffic_splits: %{
    transaction_pool: String.to_integer(System.get_env("TRANSACTION_POOL_TRAFFIC", "0")),
    sync_service: String.to_integer(System.get_env("SYNC_SERVICE_TRAFFIC", "0")),
    filter_manager: String.to_integer(System.get_env("FILTER_MANAGER_TRAFFIC", "0")),
    subscription_manager: String.get_env("SUBSCRIPTION_MANAGER_TRAFFIC", "0")
  }

# Circuit breaker configuration for V2 modules
config :mana, :circuit_breakers,
  transaction_pool_v2: [
    failure_threshold: 10,
    success_threshold: 3,
    timeout: 60_000,
    reset_timeout: 300_000
  ],
  sync_service_v2: [
    failure_threshold: 5, 
    success_threshold: 2,
    timeout: 120_000,
    reset_timeout: 600_000
  ]
```

## Deployment Phases

### Phase 1: Infrastructure Setup (Day 1-2)
**Goal**: Prepare infrastructure for V2 deployment

#### Monitoring Setup
```elixir
# config/prod.exs
config :telemetry_poller, :measurements,
  v2_module_metrics: [
    # Transaction Pool V2 metrics
    {Blockchain.SimplePoolV2, :get_stats, []},
    {Mana.Metrics, :transaction_pool_memory_usage, []},
    
    # Sync Service V2 metrics  
    {ExWire.SimpleSyncV2, :get_sync_progress, []},
    {Mana.Metrics, :sync_service_memory_usage, []}
  ]

# Grafana dashboard configuration
config :mana, :grafana_dashboards, [
  %{
    name: "V2 Module Performance",
    panels: [
      %{type: "throughput", module: "transaction_pool_v2"},
      %{type: "latency", module: "transaction_pool_v2"},
      %{type: "memory", module: "transaction_pool_v2"},
      %{type: "error_rate", module: "transaction_pool_v2"},
      %{type: "sync_speed", module: "sync_service_v2"},
      %{type: "peer_connections", module: "sync_service_v2"}
    ]
  }
]
```

#### Alerting Configuration
```elixir
# lib/mana/monitoring/alerts.ex
defmodule Mana.Monitoring.Alerts do
  @moduledoc "Production alerting for V2 modules"
  
  @alert_thresholds %{
    transaction_pool_v2: %{
      throughput_drop: 15,           # Alert if throughput drops >15%
      latency_p95_increase: 25,      # Alert if P95 latency increases >25%
      memory_usage_increase: 20,     # Alert if memory usage increases >20%
      error_rate: 2,                 # Alert if error rate >2%
      queue_size: 10_000            # Alert if queue size >10k transactions
    },
    sync_service_v2: %{
      sync_speed_drop: 20,           # Alert if sync speed drops >20%
      peer_disconnect_rate: 30,      # Alert if >30% peers disconnect
      memory_usage_increase: 25,     # Alert if memory usage increases >25%
      block_processing_delay: 60     # Alert if block processing >60s behind
    }
  }
  
  def check_v2_health do
    with {:ok, pool_health} <- check_transaction_pool_v2(),
         {:ok, sync_health} <- check_sync_service_v2() do
      {:ok, %{transaction_pool: pool_health, sync_service: sync_health}}
    else
      {:error, module, reason} ->
        Logger.error("V2 health check failed for #{module}: #{inspect(reason)}")
        trigger_alert(module, reason)
        {:error, module, reason}
    end
  end
  
  defp check_transaction_pool_v2 do
    # Implementation for checking transaction pool health
    # Compare current metrics against baselines and thresholds
  end
  
  defp check_sync_service_v2 do
    # Implementation for checking sync service health  
    # Monitor sync progress, peer connections, block processing
  end
end
```

### Phase 2: Canary Deployment (Day 3-5)
**Goal**: Deploy V2 to small subset of traffic for validation

#### Canary Configuration
```bash
# Environment variables for canary deployment
export TRANSACTION_POOL_VERSION="v2"
export TRANSACTION_POOL_TRAFFIC="5"  # 5% of traffic to V2

export SYNC_SERVICE_VERSION="v2" 
export SYNC_SERVICE_TRAFFIC="5"     # 5% of traffic to V2

# Circuit breaker settings for canary
export CIRCUIT_BREAKER_ENABLED="true"
export CIRCUIT_BREAKER_FAILURE_THRESHOLD="3"
export CIRCUIT_BREAKER_TIMEOUT="30000"
```

#### Canary Validation Checklist
- [ ] V2 modules start successfully
- [ ] 5% traffic routes to V2 without errors
- [ ] Performance metrics within acceptable ranges
- [ ] Memory usage stable
- [ ] No critical alerts triggered
- [ ] Rollback mechanism tested

### Phase 3: Gradual Rollout (Day 6-12) 
**Goal**: Incrementally increase V2 traffic while monitoring

#### Rollout Schedule
```bash
# Day 6-7: 25% traffic
export TRANSACTION_POOL_TRAFFIC="25"
export SYNC_SERVICE_TRAFFIC="25"

# Day 8-9: 50% traffic  
export TRANSACTION_POOL_TRAFFIC="50"
export SYNC_SERVICE_TRAFFIC="50"

# Day 10-11: 75% traffic
export TRANSACTION_POOL_TRAFFIC="75" 
export SYNC_SERVICE_TRAFFIC="75"

# Day 12: 90% traffic (hold before 100%)
export TRANSACTION_POOL_TRAFFIC="90"
export SYNC_SERVICE_TRAFFIC="90"
```

#### Automated Rollout Controller
```elixir
defmodule Mana.Deployment.RolloutController do
  @moduledoc "Automated V2 rollout with health monitoring"
  
  use GenServer
  require Logger
  
  @rollout_stages [5, 25, 50, 75, 90, 100]
  @health_check_interval 60_000  # Check every minute
  @stability_period 3_600_000     # Wait 1 hour between stages
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    schedule_health_check()
    
    {:ok, %{
      current_stage: 0,
      last_rollout: nil,
      health_failures: 0,
      rollout_paused: false
    }}
  end
  
  def handle_info(:health_check, state) do
    case Mana.Monitoring.Alerts.check_v2_health() do
      {:ok, _health_data} ->
        state = %{state | health_failures: 0}
        
        # Consider advancing to next stage
        new_state = maybe_advance_rollout(state)
        schedule_health_check()
        {:noreply, new_state}
        
      {:error, module, reason} ->
        Logger.error("V2 health check failed: #{module} - #{reason}")
        
        health_failures = state.health_failures + 1
        
        # Rollback if too many failures
        if health_failures >= 3 do
          Logger.error("Multiple health check failures, initiating rollback")
          initiate_rollback()
          {:noreply, %{state | rollout_paused: true}}
        else
          schedule_health_check() 
          {:noreply, %{state | health_failures: health_failures}}
        end
    end
  end
  
  defp maybe_advance_rollout(state) do
    current_stage_index = state.current_stage
    
    cond do
      # Already at final stage
      current_stage_index >= length(@rollout_stages) - 1 ->
        state
        
      # Rollout is paused
      state.rollout_paused ->
        state
        
      # Not enough time passed since last rollout
      state.last_rollout && 
      :os.system_time(:millisecond) - state.last_rollout < @stability_period ->
        state
        
      # Advance to next stage
      true ->
        next_stage_index = current_stage_index + 1
        next_traffic_percentage = Enum.at(@rollout_stages, next_stage_index)
        
        Logger.info("Advancing V2 rollout to #{next_traffic_percentage}%")
        update_traffic_split(next_traffic_percentage)
        
        %{state |
          current_stage: next_stage_index,
          last_rollout: :os.system_time(:millisecond)
        }
    end
  end
  
  defp initiate_rollback do
    Logger.error("Initiating V2 rollback to 0% traffic")
    update_traffic_split(0)
    
    # Send alerts
    Mana.Monitoring.Alerts.send_alert(:v2_rollback, %{
      reason: "Health check failures",
      timestamp: DateTime.utc_now()
    })
  end
  
  defp update_traffic_split(percentage) do
    # Update application configuration
    Application.put_env(:mana, :traffic_splits, %{
      transaction_pool: percentage,
      sync_service: percentage
    })
    
    # Persist to configuration store for other nodes
    Mana.Config.update_traffic_splits(%{
      transaction_pool: percentage,
      sync_service: percentage
    })
  end
  
  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end
end
```

### Phase 4: Full Migration (Day 13-15)
**Goal**: Complete migration to V2 and deprecate V1

#### Final Migration Steps
```bash
# Day 13: 100% traffic to V2
export TRANSACTION_POOL_TRAFFIC="100"
export SYNC_SERVICE_TRAFFIC="100"

# Day 14-15: Monitor 100% V2 traffic
# Prepare for V1 deprecation
export V1_DEPRECATION_WARNING="true"
```

#### V1 Deprecation Process
```elixir
defmodule Mana.Migration.V1Deprecation do
  @moduledoc "Handles deprecation and removal of V1 modules"
  
  def start_deprecation_process do
    Logger.info("Starting V1 module deprecation process")
    
    # Step 1: Mark V1 modules as deprecated
    mark_modules_deprecated()
    
    # Step 2: Stop V1 background processes
    stop_v1_background_processes()
    
    # Step 3: Clear V1 state (after backup)
    backup_and_clear_v1_state()
    
    # Step 4: Update documentation
    update_deprecation_docs()
    
    Logger.info("V1 deprecation process completed")
  end
  
  defp mark_modules_deprecated do
    # Add deprecation warnings to V1 modules
    deprecated_modules = [
      Blockchain.TransactionPool,
      ExWire.Sync
    ]
    
    Enum.each(deprecated_modules, fn module ->
      Logger.warn("Module #{module} is deprecated and will be removed")
    end)
  end
  
  defp stop_v1_background_processes do
    # Gracefully stop any V1-specific background processes
    # Ensure no data loss during shutdown
  end
  
  defp backup_and_clear_v1_state do
    # Create final backup of V1 state
    # Clear any persistent V1 data
  end
end
```

## Monitoring and Observability

### Key Metrics Dashboard
```elixir
# lib/mana/monitoring/v2_metrics.ex
defmodule Mana.Monitoring.V2Metrics do
  @moduledoc "Comprehensive metrics collection for V2 modules"
  
  # Transaction Pool V2 Metrics
  def collect_transaction_pool_metrics do
    %{
      # Performance metrics
      throughput_tps: get_transaction_throughput(),
      avg_latency_ms: get_average_latency(),
      p95_latency_ms: get_p95_latency(),
      p99_latency_ms: get_p99_latency(),
      
      # Resource metrics
      memory_usage_mb: get_memory_usage(:transaction_pool_v2),
      cpu_usage_percent: get_cpu_usage(:transaction_pool_v2),
      
      # Business metrics
      pool_size: get_pool_size(),
      pending_transactions: get_pending_count(),
      processed_transactions: get_processed_count(),
      rejected_transactions: get_rejected_count(),
      
      # Error metrics
      error_rate_percent: get_error_rate(),
      timeout_count: get_timeout_count(),
      circuit_breaker_state: get_circuit_breaker_state()
    }
  end
  
  # Sync Service V2 Metrics  
  def collect_sync_service_metrics do
    %{
      # Sync performance
      sync_speed_bps: get_sync_speed(),
      blocks_behind: get_blocks_behind(),
      avg_block_processing_ms: get_block_processing_time(),
      
      # Network metrics
      connected_peers: get_connected_peer_count(),
      peer_connection_success_rate: get_peer_success_rate(),
      network_bandwidth_mbps: get_network_bandwidth(),
      
      # Resource metrics
      memory_usage_mb: get_memory_usage(:sync_service_v2),
      cpu_usage_percent: get_cpu_usage(:sync_service_v2),
      
      # Queue metrics
      block_queue_size: get_block_queue_size(),
      peer_request_queue_size: get_peer_request_queue_size()
    }
  end
end
```

### Alert Rules
```yaml
# config/alerts.yml
alert_rules:
  transaction_pool_v2:
    - name: "High Transaction Pool Latency"
      condition: "avg_latency_ms > 100"
      severity: "warning"
      duration: "2m"
      
    - name: "Transaction Pool Throughput Drop"
      condition: "throughput_tps < baseline * 0.8"
      severity: "critical" 
      duration: "1m"
      
    - name: "High Transaction Pool Memory Usage"
      condition: "memory_usage_mb > 500"
      severity: "warning"
      duration: "5m"
      
    - name: "Transaction Pool Error Rate"
      condition: "error_rate_percent > 2"
      severity: "critical"
      duration: "30s"
      
  sync_service_v2:
    - name: "Slow Block Sync"
      condition: "sync_speed_bps < 10"
      severity: "warning"
      duration: "5m"
      
    - name: "High Blocks Behind"
      condition: "blocks_behind > 100"
      severity: "critical"
      duration: "2m"
      
    - name: "Low Peer Connections"
      condition: "connected_peers < 5"
      severity: "warning"
      duration: "1m"
      
    - name: "Sync Service Memory Leak"
      condition: "memory_usage_mb > 1000"
      severity: "critical"
      duration: "10m"
```

## Rollback Procedures

### Automatic Rollback Triggers
```elixir
defmodule Mana.Deployment.AutoRollback do
  @moduledoc "Automatic rollback system for V2 deployments"
  
  @rollback_triggers %{
    # Critical error rate threshold
    error_rate: 5.0,
    
    # Performance degradation thresholds
    throughput_drop: 30.0,
    latency_increase: 100.0,
    
    # Resource usage thresholds
    memory_increase: 50.0,
    cpu_increase: 80.0,
    
    # Business logic thresholds
    failed_transactions: 10.0
  }
  
  def evaluate_rollback_conditions do
    current_metrics = get_current_v2_metrics()
    baseline_metrics = get_baseline_v1_metrics()
    
    violations = check_all_conditions(current_metrics, baseline_metrics)
    
    if length(violations) > 0 do
      Logger.error("Rollback conditions met: #{inspect(violations)}")
      initiate_automatic_rollback(violations)
    else
      :ok
    end
  end
  
  defp check_all_conditions(current, baseline) do
    []
    |> check_error_rate(current, baseline)
    |> check_performance(current, baseline)
    |> check_resources(current, baseline)
  end
  
  defp initiate_automatic_rollback(violations) do
    Logger.error("INITIATING AUTOMATIC ROLLBACK: #{inspect(violations)}")
    
    # Immediately set traffic to 0% for V2
    Application.put_env(:mana, :traffic_splits, %{
      transaction_pool: 0,
      sync_service: 0
    })
    
    # Send critical alerts
    send_rollback_alert(violations)
    
    # Create incident
    create_rollback_incident(violations)
  end
end
```

### Manual Rollback Procedures
```bash
#!/bin/bash
# scripts/rollback_v2.sh - Manual rollback script

echo "=== EMERGENCY V2 ROLLBACK INITIATED ==="
echo "Timestamp: $(date)"

# Step 1: Immediately stop V2 traffic
echo "Setting V2 traffic to 0%..."
export TRANSACTION_POOL_TRAFFIC="0"
export SYNC_SERVICE_TRAFFIC="0"

# Update configuration in all environments
kubectl set env deployment/mana-app TRANSACTION_POOL_TRAFFIC=0
kubectl set env deployment/mana-app SYNC_SERVICE_TRAFFIC=0

# Step 2: Verify rollback
echo "Verifying rollback..."
sleep 30

# Check that traffic is going to V1
CURRENT_TRAFFIC=$(curl -s http://localhost:4000/health | jq '.module_versions')
echo "Current traffic routing: $CURRENT_TRAFFIC"

# Step 3: Monitor system recovery
echo "Monitoring system recovery..."
for i in {1..10}; do
    HEALTH=$(curl -s http://localhost:4000/health | jq '.status')
    echo "Health check $i: $HEALTH"
    sleep 10
done

echo "=== ROLLBACK COMPLETED ==="
echo "Next steps:"
echo "1. Investigate root cause"
echo "2. Fix V2 issues"
echo "3. Re-test V2 in staging"
echo "4. Plan new deployment"
```

## Performance Optimization

### V2 Performance Tuning
```elixir
# config/prod.exs - Production performance tuning
config :mana, Blockchain.SimplePoolV2,
  # Pool configuration
  max_pool_size: 50_000,
  cleanup_interval: 30_000,
  max_transaction_age: 1_800,
  
  # Performance tuning
  hibernate_after: 15_000,
  priority_queue_segments: 8,
  batch_processing_size: 100,
  
  # Memory management
  gc_frequency: 10_000,
  memory_limit_mb: 256

config :mana, ExWire.SimpleSyncV2,
  # Sync configuration 
  max_peer_connections: 50,
  block_request_batch_size: 128,
  peer_scoring_enabled: true,
  
  # Performance tuning
  sync_checkpoint_interval: 1000,
  peer_timeout_ms: 30_000,
  block_processing_concurrency: 4,
  
  # Memory management
  block_cache_size: 2048,
  peer_cache_size: 1000
```

### JIT Compilation Optimization
```elixir
# config/prod.exs
config :elixir, :ansi_enabled, false

# Enable JIT compilation for hot code paths
config :mana, :jit_modules, [
  Blockchain.SimplePoolV2,
  ExWire.SimpleSyncV2,
  Mana.ModuleRouter
]
```

## Security Considerations

### V2 Security Hardening
```elixir
defmodule Mana.Security.V2Hardening do
  @moduledoc "Security hardening for V2 modules"
  
  # Input validation for transaction pool
  def validate_transaction_input(raw_transaction) do
    with :ok <- validate_size(raw_transaction),
         :ok <- validate_format(raw_transaction),
         :ok <- validate_signature(raw_transaction),
         :ok <- validate_rate_limit(raw_transaction) do
      :ok
    else
      {:error, reason} -> 
        Logger.warn("Transaction validation failed: #{reason}")
        {:error, reason}
    end
  end
  
  # Rate limiting for sync service
  def check_sync_rate_limit(peer_id) do
    case :ets.lookup(:sync_rate_limits, peer_id) do
      [{^peer_id, count, last_reset}] ->
        if should_reset_limit?(last_reset) do
          :ets.insert(:sync_rate_limits, {peer_id, 1, :os.system_time(:second)})
          :ok
        else
          if count < max_requests_per_minute() do
            :ets.insert(:sync_rate_limits, {peer_id, count + 1, last_reset})
            :ok
          else
            {:error, :rate_limited}
          end
        end
      [] ->
        :ets.insert(:sync_rate_limits, {peer_id, 1, :os.system_time(:second)})
        :ok
    end
  end
end
```

## Success Criteria

### Deployment Success Metrics
- [ ] **Zero Downtime**: No service interruptions during migration
- [ ] **Performance**: V2 performance ≥ V1 baseline
- [ ] **Reliability**: Error rate ≤ 0.1% for 48 hours
- [ ] **Resource Usage**: Memory usage increase ≤ 15%
- [ ] **User Experience**: No user-facing issues reported

### Final Validation Checklist
- [ ] All V1 modules successfully deprecated
- [ ] V2 modules handling 100% production traffic
- [ ] Performance metrics exceeding baseline
- [ ] Monitoring and alerting operational
- [ ] Documentation updated
- [ ] Team trained on V2 operations

## Post-Deployment

### Cleanup Tasks
1. **Remove V1 Code**: Delete deprecated V1 modules and tests
2. **Update Documentation**: Remove V1 references, update API docs
3. **Clean Configuration**: Remove V1-specific config and feature flags
4. **Archive Metrics**: Preserve V1 performance data for future reference

### Continuous Improvement
1. **Performance Monitoring**: Ongoing optimization based on production metrics
2. **Capacity Planning**: Scale V2 modules based on growth patterns
3. **Security Updates**: Regular security reviews and updates
4. **Feature Development**: Build new features on V2 architecture

This completes the comprehensive V2 production deployment guide. The deployment is designed for maximum safety with automated monitoring, gradual rollout, and instant rollback capabilities.