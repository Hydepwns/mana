# Ethereum 2.0 Pruning System - Large Scale Testing

This document describes the comprehensive testing infrastructure for the Ethereum 2.0 pruning system, including large-scale functional tests, stress tests, performance benchmarks, and production readiness validation.

## Overview

The pruning system testing infrastructure validates the system's ability to handle production-scale datasets while maintaining performance, reliability, and correctness. The testing suite includes:

- **Large-scale functional tests** - Validates correctness with realistic data volumes
- **Stress tests** - Tests system behavior under extreme conditions  
- **Performance benchmarks** - Measures throughput, latency, and resource usage
- **Production readiness validation** - Confirms deployment readiness

## Quick Start

### Run All Tests

```bash
# Run comprehensive test suite
./run_pruning_tests.exs

# Run with specific scale
./run_pruning_tests.exs --scale large

# Run in CI mode (reduced scope)
./run_pruning_tests.exs --ci
```

### Run Specific Test Suites

```bash
# Functional tests only
./run_pruning_tests.exs --suite functional

# Stress tests with large dataset
./run_pruning_tests.exs --suite stress --scale large

# Performance benchmarks
./run_pruning_tests.exs --benchmark

# Production readiness validation  
./run_pruning_tests.exs --production
```

## Test Infrastructure Components

### 1. Test Data Generator (`test_data_generator.ex`)

Generates realistic test datasets that mirror production Ethereum 2.0 environments:

- **Network Profiles**: Mainnet, testnet, stress-test configurations
- **Data Scales**: Small (2h), Medium (24h), Large (1w), Massive (1m)
- **Realistic Patterns**: Fork structures, attestation distributions, validator evolution

```elixir
# Generate large mainnet dataset
dataset = TestDataGenerator.generate_dataset(:mainnet, :large)

# Generate stress test data with high fork probability
dataset = TestDataGenerator.generate_dataset(:stress_test, :medium, [
  fork_probability: 0.3,
  max_reorg_depth: 20
])
```

### 2. Large Scale Tests (`pruning_large_scale_test.exs`)

Comprehensive functional validation with production-scale data:

- **Fork choice pruning** with 10K-500K blocks
- **State pruning** with 50K-200K beacon states  
- **Attestation pool pruning** with millions of attestations
- **Comprehensive pruning** cycles under load
- **Memory management** validation
- **Concurrent operation** testing

**Performance Targets:**
- Fork choice: >25 MB/s throughput, <30s duration
- State pruning: >15 MB/s throughput, <60s duration  
- Attestation pruning: >5K ops/s throughput, <15s duration

### 3. Stress Tests (`pruning_stress_test.exs`)

Validates system behavior under extreme conditions:

- **Deep reorganizations** with complex fork structures
- **Massive data volumes** (1.5M validators, 500 attestations/slot)
- **Memory pressure** scenarios with concurrent operations
- **Sustained load** testing (high-frequency operations)
- **Pathological edge cases** and error conditions

**Stress Scenarios:**
```elixir
@stress_scenarios %{
  deep_reorg: %{fork_probability: 0.3, max_reorg_depth: 20},
  massive_attestations: %{validators: 1_500_000, attestations_per_slot: 500},
  memory_pressure: %{concurrent_operations: 8, state_size_multiplier: 2.0}
}
```

### 4. Performance Benchmarks (`pruning_benchmark.ex`)

Detailed performance analysis across different scenarios:

- **Throughput benchmarks** - Maximum performance measurement
- **Scalability analysis** - Performance vs dataset size relationships
- **Memory profiling** - Memory usage patterns and efficiency
- **Concurrency testing** - Multi-worker performance scaling
- **Realistic scenarios** - Real-world usage pattern simulation

**Benchmark Types:**
- Throughput: MB/s or operations/s under optimal conditions
- Scalability: How performance changes with dataset size
- Memory: Memory usage patterns and garbage collection effectiveness
- Concurrency: Performance scaling with multiple workers

### 5. Test Runner (`pruning_test_runner.ex`)

Orchestrates comprehensive test execution:

- **Suite Management** - Coordinates different test types
- **Production Validation** - Validates deployment readiness
- **Report Generation** - Creates detailed HTML/JSON reports
- **CI Integration** - Supports automated testing pipelines

## Test Data Characteristics

### Network Profiles

**Mainnet Profile:**
- 900K validators
- 128 attestations/slot average
- 5% fork probability
- 7-block max reorg depth

**Testnet Profile:**  
- 100K validators
- 64 attestations/slot average
- 8% fork probability (higher instability)
- 5-block max reorg depth

**Stress Test Profile:**
- 1.5M validators
- 256 attestations/slot average  
- 15% fork probability (very high)
- 12-block max reorg depth

### Data Scales

| Scale | Duration | Fork Choice Blocks | Beacon States | Storage Est. |
|-------|----------|-------------------|---------------|--------------|
| Small | 2 hours  | 1K               | 500           | ~1 GB        |
| Medium| 24 hours | 10K              | 5K            | ~10 GB       |
| Large | 1 week   | 100K             | 50K           | ~100 GB      |
| Massive| 1 month | 500K             | 200K          | ~500 GB      |

## Performance Expectations

### Production Targets

| Strategy | Throughput | Max Duration | Memory Efficiency |
|----------|------------|--------------|------------------|
| Fork Choice | >50 MB/s | <30s | >90% |
| State Trie | >20 MB/s | <60s | >80% |  
| Attestations | >5K ops/s | <15s | >95% |
| Blocks | >30 MB/s | <45s | >85% |

### System Resource Limits

- **Memory Growth**: <500MB during pruning operations
- **CPU Usage**: <25% average during normal operations
- **I/O Pattern**: Bursty, <100 MB/min sustained average
- **Success Rate**: >95% operation success rate

## Test Execution Modes

### CI Mode

Optimized for continuous integration environments:
```bash
./run_pruning_tests.exs --ci
```

- Uses small dataset scale
- Runs essential functional tests only
- 5-10 minute execution time
- Fail-fast on critical errors

### Development Mode

For local development and debugging:
```bash
./run_pruning_tests.exs --suite functional --scale medium
```

- Moderate dataset sizes
- Detailed logging enabled
- Individual strategy testing
- Performance profiling

### Production Validation

Comprehensive readiness assessment:
```bash
./run_pruning_tests.exs --production
```

- Large-scale dataset validation
- Performance threshold verification
- Operational procedure testing
- Monitoring coverage validation

### Stress Testing

Extreme condition validation:
```bash
./run_pruning_tests.exs --suite stress --scale large
```

- Pathological data patterns
- Resource exhaustion scenarios
- Error recovery validation
- Breaking point identification

## Interpreting Results

### Test Status Indicators

- **✅ PASS** - All requirements met
- **⚠️ WARNING** - Minor issues, deployment possible with monitoring
- **❌ FAIL** - Critical issues, do not deploy

### Performance Analysis

Results include detailed metrics:
```json
{
  "strategy": "fork_choice",
  "performance": {
    "avg_duration_ms": 15000,
    "throughput_mb_per_sec": 65.5,
    "meets_targets": true
  },
  "recommendations": [
    "Performance meets all targets",
    "Consider increasing batch size for better throughput"
  ]
}
```

### Memory Profiling

Memory usage is tracked throughout operations:
- Peak memory consumption
- Growth patterns over time
- Garbage collection effectiveness
- Memory leak detection

## Troubleshooting

### Common Issues

**High Memory Usage:**
```bash
# Check memory profiling in results
cat test_results/memory_results.json

# Run with reduced concurrency
PRUNING_MAX_WORKERS=2 ./run_pruning_tests.exs --suite stress
```

**Performance Below Targets:**
```bash
# Run detailed benchmark analysis
./run_pruning_tests.exs --benchmark

# Check system resources
htop  # Monitor CPU/memory during tests
```

**Test Failures:**
```bash
# Run with verbose logging
ELIXIR_LOG_LEVEL=debug ./run_pruning_tests.exs --suite functional

# Check specific test output
cat test_results/functional_results.json
```

### Environment Configuration

**Test Scale Configuration:**
```bash
export PRUNING_TEST_SCALE=large    # small, medium, large, massive
export PRUNING_MAX_WORKERS=4       # Concurrent worker limit
export PRUNING_CI_MODE=true        # Enable CI optimizations
```

**Memory Limits:**
```bash
export ELIXIR_ERL_OPTIONS="+A 64 +P 5000000 +Q 2000000"  # Increase limits
```

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Pruning System Tests
on: [push, pull_request]

jobs:
  pruning-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-elixir@v1
        with:
          elixir-version: '1.15'
          otp-version: '26'
      - name: Run Pruning Tests
        run: |
          ./run_pruning_tests.exs --ci
        env:
          PRUNING_TEST_SCALE: small
          PRUNING_CI_MODE: true
```

### Performance Monitoring

Track performance regressions over time:
```bash
# Generate benchmark baseline
./run_pruning_tests.exs --benchmark --output baseline_results

# Compare against baseline in CI
./scripts/compare_performance.exs baseline_results test_results
```

## Advanced Testing Scenarios

### Custom Data Generation

```elixir
# Generate specialized test data
dataset = TestDataGenerator.generate_dataset(:mainnet, :large, [
  fork_probability: 0.2,        # Custom fork rate
  max_reorg_depth: 15,          # Deep reorgs
  validator_count: 1_200_000    # Custom validator count
])
```

### Isolated Strategy Testing

```elixir
# Test specific pruning strategy
ExWire.Eth2.PruningBenchmark.quick_benchmark(:fork_choice, :large)

# Test with custom configuration
config = PruningConfig.get_preset(:mainnet) |> elem(1)
custom_config = Map.merge(config, %{max_concurrent_pruners: 8})
```

### Production Simulation

```elixir
# Simulate realistic operational patterns
ExWire.Eth2.PruningTestRunner.validate_production_readiness([
  scenario_duration_minutes: 60,
  operation_frequency: 12,      # 12 operations per minute
  data_growth_rate: 100         # 100 MB per minute
])
```

## Contributing

When adding new tests:

1. **Follow existing patterns** - Use established test structure
2. **Include performance validation** - Always measure and validate performance
3. **Add stress scenarios** - Include edge cases and error conditions  
4. **Document expectations** - Clearly define what constitutes success
5. **Update thresholds** - Keep performance targets current

### Adding New Test Cases

```elixir
defmodule ExWire.Eth2.MyPruningTest do
  use ExUnit.Case, async: false
  
  @moduletag :large_scale
  @moduletag timeout: 300_000
  
  setup do
    dataset = TestDataGenerator.generate_dataset(:mainnet, :medium)
    %{dataset: dataset}
  end
  
  test "validates new pruning strategy", %{dataset: dataset} do
    # Test implementation with performance validation
    start_time = System.monotonic_time(:millisecond)
    
    {:ok, result} = MyPruningStrategy.prune(dataset)
    
    duration_ms = System.monotonic_time(:millisecond) - start_time
    
    # Validate correctness
    assert result.success_count > 0
    
    # Validate performance  
    assert duration_ms < 30_000
    assert result.throughput_mb_per_sec > 25.0
    
    # Record metrics
    PruningMetrics.record_operation(:my_strategy, :ok, duration_ms)
  end
end
```

## References

- [Pruning System Architecture](./apps/ex_wire/lib/ex_wire/eth2/pruning_system_guide.md)
- [Performance Benchmarking Results](./test_results/)
- [Ethereum 2.0 Specification](https://github.com/ethereum/consensus-specs)
- [Mana Client Documentation](./README.md)