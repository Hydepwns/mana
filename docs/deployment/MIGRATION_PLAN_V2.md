# V1 to V2 Migration Plan

## Overview
This document outlines the migration strategy from V1 modules to V2 modules, ensuring zero-downtime deployment and maintaining backward compatibility.

## Current Status

### ✅ Completed
- **V2 Module Templates**: SimplePoolV2 and SimpleSyncV2 implemented and tested
- **Test Infrastructure**: Comprehensive test suites with 90%+ pass rates
- **Compilation Issues**: Fixed major compilation problems blocking V2 adoption

### 🚧 V2 Modules Ready for Migration
1. **Blockchain.SimplePoolV2** - Transaction pool with improved state management
2. **ExWire.SimpleSyncV2** - Block synchronization with better peer management
3. **Test Suites** - Comprehensive coverage for both modules

## Migration Strategy

### Phase 1: V2 Implementation Completion (1-2 weeks)
**Goal**: Complete V2 implementations for all critical modules

#### Week 1: Core Module Migration
- [ ] **TransactionPool**: Migrate `Blockchain.TransactionPool` to V2 architecture
  - Use SimplePoolV2 as template
  - Implement production-grade transaction validation
  - Add advanced priority queue management
  - Migrate existing tests and add V2-specific tests

- [ ] **Sync Service**: Migrate `ExWire.Sync` to V2 architecture  
  - Use SimpleSyncV2 as template
  - Implement proper P2P block synchronization
  - Add warp sync capabilities
  - Enhance peer scoring and management

#### Week 2: Supporting Modules
- [ ] **FilterManager**: Complete V2 implementation
  - Fix placeholder implementations
  - Add proper WebSocket/HTTP subscription handling
  - Implement filter lifecycle management

- [ ] **SubscriptionManager**: Complete V2 implementation
  - Real-time event subscription handling
  - Connection lifecycle management
  - Performance optimizations

### Phase 2: Parallel Deployment (1 week)
**Goal**: Run V1 and V2 modules side-by-side for testing

#### Configuration Strategy
```elixir
# config/config.exs
config :mana, :module_versions,
  transaction_pool: System.get_env("TRANSACTION_POOL_VERSION", "v1"), # v1 or v2
  sync_service: System.get_env("SYNC_SERVICE_VERSION", "v1"),         # v1 or v2
  filter_manager: System.get_env("FILTER_MANAGER_VERSION", "v1"),     # v1 or v2
  subscription_manager: System.get_env("SUBSCRIPTION_MANAGER_VERSION", "v1") # v1 or v2
```

#### Module Router Pattern
```elixir
defmodule Blockchain.TransactionPoolRouter do
  @moduledoc "Routes to V1 or V2 based on configuration"
  
  def add_transaction(tx) do
    case Application.get_env(:mana, :module_versions)[:transaction_pool] do
      "v2" -> Blockchain.TransactionPoolV2.add_transaction(tx)
      _ -> Blockchain.TransactionPool.add_transaction(tx)
    end
  end
  
  # ... other methods
end
```

#### Testing Strategy
- **A/B Testing**: Route 10% of traffic to V2 modules initially
- **Metric Comparison**: Compare performance, memory usage, error rates
- **Rollback Plan**: Immediate fallback to V1 if issues detected

### Phase 3: Gradual Migration (2 weeks)
**Goal**: Progressively increase V2 traffic while monitoring

#### Week 1: Low-Risk Migration
- **Day 1-2**: 10% traffic to V2 (test environment only)
- **Day 3-4**: 25% traffic to V2 (staging environment)
- **Day 5-7**: 50% traffic to V2 (staging + limited production)

#### Week 2: Production Migration
- **Day 1-2**: 25% production traffic to V2
- **Day 3-4**: 50% production traffic to V2
- **Day 5-7**: 75% production traffic to V2

### Phase 4: Full Migration (1 week)
**Goal**: Complete migration to V2 and deprecate V1

#### Migration Completion
- **Day 1-2**: 100% traffic to V2
- **Day 3-4**: Monitor and optimize V2 performance
- **Day 5-7**: Remove V1 modules and update documentation

## Technical Implementation

### 1. Module Versioning
```elixir
# apps/blockchain/lib/blockchain/transaction_pool_v2.ex
defmodule Blockchain.TransactionPoolV2 do
  @version "2.0.0"
  @migration_compatible true
  
  # V2 implementation with backward compatibility
end
```

### 2. Configuration Management
```elixir
# config/runtime.exs
import Config

config :mana,
  module_versions: %{
    transaction_pool: System.get_env("TRANSACTION_POOL_VERSION", "v1"),
    sync_service: System.get_env("SYNC_SERVICE_VERSION", "v1")
  }
```

### 3. Feature Flags
```elixir
defmodule Mana.FeatureFlags do
  def v2_enabled?(module) do
    case module do
      :transaction_pool -> 
        Application.get_env(:mana, :module_versions)[:transaction_pool] == "v2"
      :sync_service -> 
        Application.get_env(:mana, :module_versions)[:sync_service] == "v2"
      _ -> false
    end
  end
end
```

### 4. Migration Utilities
```elixir
defmodule Mana.Migration.V2Migrator do
  @moduledoc "Utilities for migrating from V1 to V2"
  
  def migrate_transaction_pool_state(v1_state) do
    # Convert V1 state format to V2 format
    %Blockchain.TransactionPoolV2{
      transactions: v1_state.transactions,
      by_address: build_address_index(v1_state.transactions),
      stats: convert_stats(v1_state),
      config: %{}
    }
  end
  
  def migrate_sync_state(v1_state) do
    # Convert V1 sync state to V2 format
    %ExWire.SimpleSyncV2{
      chain: v1_state.chain,
      block_queue: v1_state.block_queue,
      peer_connections: convert_peers(v1_state.peers),
      sync_status: v1_state.status,
      current_block: v1_state.current_block,
      highest_block: v1_state.highest_block,
      metrics: build_metrics(v1_state),
      config: %{}
    }
  end
end
```

## Monitoring and Rollback

### Performance Metrics
Monitor these key metrics during migration:

#### Transaction Pool Metrics
- **Throughput**: Transactions processed per second
- **Latency**: Time from submission to inclusion
- **Memory Usage**: Pool size and memory consumption
- **Error Rate**: Failed transaction validations

#### Sync Service Metrics  
- **Sync Speed**: Blocks synchronized per minute
- **Peer Management**: Connection success/failure rates
- **Memory Usage**: Block queue and peer data storage
- **Network Efficiency**: Bandwidth utilization

### Alerting Thresholds
```elixir
# config/prod.exs
config :mana, :monitoring,
  alerts: %{
    transaction_pool: %{
      throughput_drop: 20,      # Alert if throughput drops >20%
      latency_increase: 50,     # Alert if latency increases >50%
      memory_increase: 30,      # Alert if memory usage increases >30%
      error_rate: 5             # Alert if error rate >5%
    },
    sync_service: %{
      sync_speed_drop: 25,      # Alert if sync speed drops >25%
      peer_disconnect: 50,      # Alert if >50% peer disconnections
      memory_increase: 40,      # Alert if memory usage increases >40%
    }
  }
```

### Automated Rollback
```elixir
defmodule Mana.Migration.AutoRollback do
  @moduledoc "Automatic rollback if V2 performance degrades"
  
  def check_and_rollback do
    with {:ok, metrics} <- get_current_metrics(),
         :ok <- validate_performance(metrics) do
      :ok
    else
      {:error, :performance_degraded} ->
        Logger.error("V2 performance degraded, initiating rollback")
        rollback_to_v1()
      error ->
        Logger.warn("Rollback check failed: #{inspect(error)}")
    end
  end
  
  defp rollback_to_v1 do
    # Immediate rollback to V1 modules
    Application.put_env(:mana, :module_versions, %{
      transaction_pool: "v1",
      sync_service: "v1",
      filter_manager: "v1", 
      subscription_manager: "v1"
    })
    
    # Restart affected services
    restart_services()
  end
end
```

## Testing Strategy

### Unit Testing
- **V2 Module Tests**: Comprehensive coverage for all V2 modules
- **Migration Tests**: Verify state migration from V1 to V2
- **Router Tests**: Ensure proper routing between V1/V2

### Integration Testing
- **End-to-End**: Full transaction flow through V2 modules  
- **Load Testing**: Performance under high transaction volumes
- **Chaos Testing**: Behavior during network/peer failures

### Production Testing
- **Canary Deployments**: Gradual rollout with monitoring
- **Shadow Testing**: V2 processes real traffic without affecting responses
- **Feature Flags**: Enable/disable V2 features without deployments

## Risk Mitigation

### High-Priority Risks
1. **Data Loss**: State migration failures
   - **Mitigation**: Comprehensive backup before migration
   - **Recovery**: Automated state restoration from backup

2. **Performance Degradation**: V2 slower than V1
   - **Mitigation**: Extensive performance testing
   - **Recovery**: Automated rollback based on metrics

3. **API Compatibility**: V2 breaks existing integrations
   - **Mitigation**: Maintain API compatibility layer
   - **Recovery**: Router can maintain V1 API with V2 backend

### Medium-Priority Risks
1. **Memory Leaks**: V2 modules consume more memory
   - **Mitigation**: Memory profiling and limits
   - **Recovery**: Process restart mechanisms

2. **Network Issues**: V2 sync causes network problems
   - **Mitigation**: Rate limiting and circuit breakers
   - **Recovery**: Fallback to V1 sync mechanisms

## Success Criteria

### Migration Complete When:
- [ ] All production traffic running on V2 modules
- [ ] Performance metrics equal or better than V1
- [ ] Zero data loss during migration
- [ ] All tests passing at 95%+ rate
- [ ] Error rates below baseline thresholds
- [ ] V1 modules successfully deprecated and removed

### Performance Targets:
- **Transaction Pool**: ≥20% improvement in throughput
- **Sync Service**: ≥15% improvement in sync speed  
- **Memory Usage**: ≤10% increase acceptable
- **API Latency**: ≤5% increase acceptable

## Timeline Summary

| Phase | Duration | Key Deliverables |
|-------|----------|------------------|
| Phase 1 | 2 weeks | Complete V2 implementations |
| Phase 2 | 1 week | Parallel deployment setup |
| Phase 3 | 2 weeks | Gradual traffic migration |
| Phase 4 | 1 week | Full migration and V1 deprecation |
| **Total** | **6 weeks** | **Full V2 migration complete** |

## Next Actions

### Immediate (Next 3 days)
1. Complete TransactionPoolV2 implementation based on SimplePoolV2
2. Set up configuration-based module routing
3. Create comprehensive migration tests

### Short-term (Next week)
1. Implement monitoring and alerting infrastructure
2. Create automated rollback mechanisms
3. Begin parallel deployment setup

### Medium-term (Next 2 weeks)
1. Start gradual traffic migration
2. Monitor performance metrics closely
3. Optimize V2 implementations based on real traffic