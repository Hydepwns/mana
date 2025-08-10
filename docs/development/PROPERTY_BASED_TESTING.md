# Property-Based Testing Framework for Mana-Ethereum

## Overview

This document provides comprehensive guidance on using and extending the property-based testing framework implemented for the Mana-Ethereum client. Property-based testing is a powerful testing methodology that generates random inputs to verify that your code satisfies certain properties or invariants under a wide range of conditions.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Framework Architecture](#framework-architecture)
3. [Writing Property Tests](#writing-property-tests)
4. [Generators](#generators)
5. [Test Execution](#test-execution)
6. [Reporting and Analysis](#reporting-and-analysis)
7. [CI/CD Integration](#cicd-integration)
8. [Best Practices](#best-practices)
9. [Troubleshooting](#troubleshooting)
10. [Examples](#examples)

## Quick Start

### Running Property Tests

```bash
# Run all property tests
mix test --include property_test

# Run specific test module
mix test apps/blockchain/test/blockchain/property_tests/transaction_property_test.exs --include property_test

# Run fuzzing tests (more intensive)
mix test --include fuzzing --timeout 300000

# Run with custom configuration
PROPERTY_TEST_MAX_RUNS=500 mix test --include property_test
```

### Basic Property Test Structure

```elixir
defmodule MyApp.PropertyTests.ExampleTest do
  use Blockchain.PropertyTesting.Framework

  property_test "list reverse is involutive" do
    check all list <- list_of(integer()) do
      assert Enum.reverse(Enum.reverse(list)) == list
    end
  end
end
```

## Framework Architecture

The property-based testing framework consists of several key components:

### Core Modules

- **`Blockchain.PropertyTesting.Framework`** - Main testing macros and utilities
- **`Blockchain.PropertyTesting.Generators`** - Data generators for blockchain structures
- **`Blockchain.PropertyTesting.Properties`** - Reusable property definitions
- **`Blockchain.PropertyTesting.Runner`** - Test execution and orchestration
- **`Blockchain.PropertyTesting.Reporter`** - Report generation and analysis

### Test Modules

- **Transaction Tests** (`apps/blockchain/test/blockchain/property_tests/transaction_property_test.exs`)
- **EVM Tests** (`apps/evm/test/evm/property_tests/evm_property_test.exs`)
- **Cryptographic Tests** (`apps/exth_crypto/test/exth_crypto/property_tests/crypto_property_test.exs`)
- **P2P Tests** (`apps/ex_wire/test/ex_wire/property_tests/p2p_property_test.exs`)
- **Fuzzing Tests** (`apps/blockchain/test/blockchain/property_tests/fuzzing_test.exs`)

## Writing Property Tests

### Using the Framework

Import the framework in your test module:

```elixir
defmodule MyApp.PropertyTests.MyTest do
  use Blockchain.PropertyTesting.Framework
  
  # Your property tests here
end
```

### Property Test Macros

#### `property_test/2`
Basic property test with configurable options:

```elixir
property_test "addition is commutative", max_runs: 1000 do
  check all {a, b} <- {integer(), integer()} do
    assert a + b == b + a
  end
end
```

#### `test_deterministic/2`
Tests that a function is deterministic:

```elixir
test_deterministic(&my_hash_function/1, binary())
```

#### `test_roundtrip/3`
Tests encode/decode roundtrip properties:

```elixir
test_roundtrip(&encode_transaction/1, &decode_transaction/1, transaction())
```

#### `fuzz_test/4`
Intensive fuzzing with error handling:

```elixir
fuzz_test "transaction processing robustness",
          &process_transaction/1,
          malformed_transaction(),
          max_runs: 5000,
          crash_on_error: false
```

### Test Types

#### 1. Invariant Tests
Verify that certain properties always hold:

```elixir
property_test "stack size never exceeds limit" do
  check all operations <- list_of(stack_operation()) do
    final_stack = execute_operations(operations)
    assert Stack.size(final_stack) <= 1024
  end
end
```

#### 2. Roundtrip Tests
Test serialization/deserialization:

```elixir
property_test "transaction serialization roundtrip" do
  check all tx <- transaction() do
    serialized = Transaction.serialize(tx)
    deserialized = Transaction.deserialize(serialized)
    assert transactions_equivalent?(tx, deserialized)
  end
end
```

#### 3. Mathematical Properties
Verify mathematical relationships:

```elixir
property_test "hash avalanche effect" do
  check all input <- binary(min_length: 1, max_length: 100),
            bit_pos <- integer(0..bit_size(input) - 1) do
    
    original_hash = hash_function(input)
    modified_hash = hash_function(flip_bit(input, bit_pos))
    
    hamming_distance = calculate_hamming_distance(original_hash, modified_hash)
    assert hamming_distance >= bit_size(original_hash) / 4
  end
end
```

#### 4. Error Handling Tests
Verify graceful error handling:

```elixir
property_test "handles malformed input gracefully" do
  check all malformed_data <- malformed_transaction() do
    result = Transaction.validate(malformed_data)
    assert match?({:error, _}, result)
  end
end
```

## Generators

The framework provides extensive data generators for blockchain-specific structures.

### Built-in Generators

```elixir
# Basic blockchain types
ethereum_address()      # 20-byte Ethereum address
wei_amount()           # Wei amounts with realistic distribution
gas_limit()            # Gas limits within valid ranges
transaction()          # Complete transaction structures
block()                # Block structures with valid headers
block_header()         # Block headers with proper fields

# Cryptographic types  
private_key()          # Valid secp256k1 private keys
public_key()           # Corresponding public keys
signature()            # ECDSA signatures

# Network types
peer_info()            # P2P peer information
p2p_message()          # Network protocol messages
```

### Custom Generators

Create domain-specific generators:

```elixir
defp contract_creation_transaction() do
  gen all nonce <- non_neg_integer(),
          gas_price <- integer(1..1_000_000_000),
          gas_limit <- integer(21_000..10_000_000),
          value <- wei_amount(),
          init_code <- binary(min_length: 0, max_length: 24000),
          v <- integer(27..28),
          r <- integer(1..(secp256k1_order() - 1)),
          s <- integer(1..(secp256k1_order() - 1)) do
    
    %Transaction{
      nonce: nonce,
      gas_price: gas_price,
      gas_limit: gas_limit,
      to: <<>>,  # Empty for contract creation
      value: value,
      data: <<>>,
      init: init_code,
      v: v,
      r: r,
      s: s
    }
  end
end
```

### Generator Composition

Combine generators for complex scenarios:

```elixir
defp blockchain_state_transition() do
  gen all initial_state <- world_state(),
          transactions <- list_of(valid_transaction(), min_length: 1, max_length: 100),
          block_number <- integer(1..1_000_000) do
    
    %{
      initial_state: initial_state,
      transactions: transactions,
      block_number: block_number
    }
  end
end
```

## Test Execution

### Local Execution

```bash
# Standard property test run
mix test --include property_test --timeout 120000

# Extended fuzzing session
mix test --include fuzzing --timeout 3600000

# Continuous testing (runs until stopped)
mix run -e "
Blockchain.PropertyTesting.Runner.run_continuous([
  Blockchain.PropertyTests.TransactionPropertyTest,
  EVM.PropertyTests.EVMPropertyTest
], max_time: 1800000)  # 30 minutes
"
```

### Configuration

Set environment variables or application config:

```elixir
# config/test.exs
config :blockchain,
  property_test_runs: 200,
  property_test_max_shrinking_steps: 100,
  property_test_timeout: 60_000
```

```bash
# Environment variables
export PROPERTY_TEST_MAX_RUNS=500
export PROPERTY_TEST_SHRINKING_STEPS=50
export PROPERTY_TEST_PARALLEL=true
```

### Advanced Execution

Use the Runner module for programmatic control:

```elixir
alias Blockchain.PropertyTesting.Runner

# Run with custom configuration
test_modules = [
  Blockchain.PropertyTests.TransactionPropertyTest,
  EVM.PropertyTests.EVMPropertyTest
]

results = Runner.run(test_modules, [
  max_runs: 1000,
  parallel: true,
  report_format: :all,
  output_dir: "custom_results",
  collect_counterexamples: true
])

# Performance benchmarking
benchmark_results = Runner.benchmark_tests(test_modules, [
  benchmark_runs: 10,
  warmup_runs: 3
])

# Regression testing
Runner.run_regression_tests("counterexamples.bin", [
  report_format: :json
])
```

## Reporting and Analysis

### Report Formats

The framework generates multiple report formats:

#### Console Output
Real-time progress and summary:
```
================================================================================
PROPERTY TEST RESULTS SUMMARY
================================================================================
Timestamp: 2024-01-15 10:30:45.123456Z
Duration: 5.2m
Modules: 4
Total Tests: 156

Results:
  ✓ Passed: 152 (97.44%)
  ✗ Failed: 4

COUNTEREXAMPLES FOUND:
----------------------------------------
1. Type: transaction_counterexample
   Reason: Extreme values caused overflow
```

#### JSON Reports
Machine-readable detailed results:
```json
{
  "summary": {
    "timestamp": "2024-01-15T10:30:45.123456Z",
    "success_rate": 0.9744,
    "total_tests": 156,
    "total_passed": 152,
    "total_failed": 4
  },
  "modules": [...],
  "counterexamples": [...],
  "statistics": {...}
}
```

#### HTML Dashboard
Interactive visualizations with charts and detailed breakdowns.

#### JUnit XML
CI/CD integration format:
```xml
<testsuite name="PropertyTests" tests="156" failures="4" errors="0">
  <testcase name="transaction_roundtrip" classname="TransactionTest" time="0.045"/>
  <testcase name="evm_stack_invariants" classname="EVMTest" time="0.123">
    <failure message="Stack overflow not detected">...</failure>
  </testcase>
</testsuite>
```

### Statistics and Metrics

The framework collects comprehensive metrics:

- **Execution Statistics**: Run counts, timing, memory usage
- **Failure Analysis**: Counterexample patterns, failure rates
- **Performance Metrics**: Tests per second, slowest operations
- **Shrinking Statistics**: Minimization effectiveness
- **Coverage Analysis**: Input space exploration

### Trend Analysis

Compare results across multiple runs:

```elixir
# Generate trend report from historical data
Reporter.generate_trend_report(historical_summaries, config)
```

## CI/CD Integration

### GitHub Actions Workflow

The framework includes a comprehensive GitHub Actions workflow (`.github/workflows/property-testing.yml`) that provides:

#### Property Test Matrix
- Parallel execution across test suites
- Configurable test duration and intensity
- Artifact collection and reporting

#### Continuous Fuzzing
- Scheduled daily fuzzing runs
- Long-running intensive testing
- Automatic issue creation on failures
- Crash dump collection

#### Performance Benchmarking
- Performance regression detection
- Benchmark result comparison
- PR comment integration

#### Regression Testing
- Counterexample preservation
- Automatic regression verification
- Historical failure analysis

### Workflow Configuration

Trigger workflows with custom parameters:

```yaml
workflow_dispatch:
  inputs:
    test_duration:
      description: 'Test duration in minutes'
      default: '30'
    max_runs_per_test:
      description: 'Maximum runs per property test'  
      default: '200'
    enable_fuzzing:
      description: 'Enable intensive fuzzing'
      type: boolean
      default: false
```

### Integration with Other CI Systems

#### Jenkins
```groovy
pipeline {
    agent any
    stages {
        stage('Property Tests') {
            steps {
                sh 'mix test --include property_test --formatter junit --output-dir test-results'
            }
            post {
                always {
                    publishTestResults(testResultsPattern: 'test-results/*.xml')
                    archiveArtifacts(artifacts: 'test_results/**/*', allowEmptyArchive: true)
                }
            }
        }
    }
}
```

#### GitLab CI
```yaml
property_tests:
  script:
    - mix test --include property_test
  artifacts:
    reports:
      junit: test_results/property_test_junit.xml
    paths:
      - test_results/
    expire_in: 30 days
```

## Best Practices

### 1. Generator Design

**Do:**
- Use realistic data distributions
- Include edge cases explicitly
- Compose simple generators into complex ones
- Document generator semantics

**Don't:**
- Generate completely uniform random data
- Ignore domain constraints
- Create overly complex generators
- Forget about boundary conditions

Example:
```elixir
# Good: Realistic gas price distribution
defp gas_price() do
  frequency([
    {50, integer(1..20_000_000_000)},      # Normal range
    {30, integer(20_000_000_000..100_000_000_000)}, # High but reasonable
    {15, integer(100_000_000_000..1_000_000_000_000)}, # Very high
    {4, constant(0)},                      # Edge case: zero
    {1, constant((1 <<< 256) - 1)}        # Edge case: maximum
  ])
end

# Bad: Uniform distribution over entire range
defp gas_price_bad() do
  integer(0..(1 <<< 256) - 1)
end
```

### 2. Property Selection

Focus on properties that are:
- **Fundamental**: Core invariants of your system
- **Universal**: True across all valid inputs
- **Testable**: Can be verified programmatically
- **Meaningful**: Catching them prevents real bugs

Good properties:
```elixir
# Determinism
property_test "hash function is deterministic" do
  check all input <- binary() do
    assert hash(input) == hash(input)
  end
end

# Inverse operations
property_test "encode/decode roundtrip" do
  check all data <- transaction() do
    assert decode(encode(data)) == data
  end
end

# Mathematical properties
property_test "addition is commutative" do
  check all {a, b} <- {integer(), integer()} do
    assert add(a, b) == add(b, a)
  end
end
```

### 3. Test Organization

Structure tests logically:

```elixir
defmodule MyApp.PropertyTests.TransactionTest do
  use Blockchain.PropertyTesting.Framework
  
  # Group 1: Structural properties
  property_test "transaction fields have correct types" do
    # ...
  end
  
  property_test "transaction addresses are valid length" do
    # ...
  end
  
  # Group 2: Behavioral properties  
  property_test "transaction execution is deterministic" do
    # ...
  end
  
  property_test "gas calculation is monotonic" do
    # ...
  end
  
  # Group 3: Edge cases and error conditions
  property_test "handles invalid signatures gracefully" do
    # ...
  end
  
  property_test "rejects transactions with insufficient gas" do
    # ...
  end
end
```

### 4. Performance Considerations

- Start with small `max_runs` during development
- Use `frequency/1` to bias generators toward interesting cases
- Profile slow tests and optimize generators
- Run expensive tests only in CI

```elixir
# Development: Quick feedback
property_test "basic invariant", max_runs: 20 do
  # ...
end

# CI: Thorough testing  
property_test "comprehensive invariant", max_runs: 1000 do
  # ...
end
```

### 5. Shrinking Strategy

Help the framework find minimal counterexamples:

```elixir
# Good: Simple, composable generators shrink well
defp simple_transaction() do
  gen all nonce <- non_neg_integer(),
          gas_price <- pos_integer(),
          gas_limit <- pos_integer() do
    %Transaction{nonce: nonce, gas_price: gas_price, gas_limit: gas_limit}
  end
end

# Problematic: Complex conditional logic
defp complex_transaction() do
  gen all base <- transaction() do
    if base.nonce > 1000 do
      %{base | gas_price: base.gas_price * 2}
    else
      base
    end
  end
end
```

## Troubleshooting

### Common Issues

#### 1. Test Timeouts
**Symptoms**: Tests hang or timeout
**Solutions**:
- Reduce `max_runs` during development
- Check for infinite loops in generators
- Profile slow operations
- Use `timeout` option in test configuration

```elixir
property_test "fast property", max_runs: 50, timeout: 5000 do
  check all data <- simple_generator() do
    assert fast_operation(data)
  end
end
```

#### 2. Poor Shrinking
**Symptoms**: Large, complex counterexamples
**Solutions**:
- Use built-in generators when possible
- Avoid complex conditional logic in generators
- Compose simple generators
- Manually implement custom shrinking if needed

#### 3. Flaky Tests
**Symptoms**: Tests sometimes pass, sometimes fail
**Solutions**:
- Check for non-deterministic operations
- Avoid depending on system time or random values
- Use deterministic seeds for testing
- Increase `max_runs` to surface intermittent issues

#### 4. Memory Issues
**Symptoms**: Out of memory errors during testing
**Solutions**:
- Limit generator output size
- Use streaming generators for large data
- Monitor memory usage with framework tools
- Run tests with higher memory limits

```elixir
# Limit memory usage
with_memory_tracking do
  property_test "memory-conscious test" do
    check all data <- binary(max_length: 1000) do  # Limit size
      assert process_data(data)
    end
  end
end
```

### Debugging Property Tests

#### 1. Add Logging
```elixir
property_test "debug example" do
  check all input <- my_generator() do
    IO.inspect(input, label: "Testing with")
    result = my_function(input)
    IO.inspect(result, label: "Result")
    assert some_property(result)
  end
end
```

#### 2. Use Specific Seeds
```elixir
# Reproduce a specific failure
property_test "reproducible test" do
  check all input <- my_generator(),
            max_runs: 1 do
    # This will use the same seed each time
    assert my_property(input)
  end
end
```

#### 3. Manual Counterexamples
```elixir
# Test specific problematic cases
test "manual counterexample" do
  problematic_input = %Transaction{nonce: 0, gas_price: 0, gas_limit: 0}
  assert_raise ArgumentError, fn ->
    Transaction.validate(problematic_input)
  end
end
```

## Examples

### Example 1: Transaction Validation

```elixir
defmodule Blockchain.PropertyTests.TransactionValidationTest do
  use Blockchain.PropertyTesting.Framework
  
  alias Blockchain.Transaction
  
  property_test "valid transactions pass validation" do
    check all tx <- valid_transaction() do
      assert {:ok, _} = Transaction.validate(tx)
    end
  end
  
  property_test "transactions with zero gas limit fail validation" do
    check all tx <- transaction(),
              tx.gas_limit == 0 do
      assert {:error, :insufficient_gas} = Transaction.validate(tx)
    end
  end
  
  property_test "transaction intrinsic gas is monotonic with data size" do
    check all base_tx <- transaction(),
              {data1, data2} <- {binary(), binary()},
              byte_size(data1) <= byte_size(data2) do
      
      tx1 = %{base_tx | data: data1}
      tx2 = %{base_tx | data: data2}
      
      gas1 = Transaction.intrinsic_gas(tx1)
      gas2 = Transaction.intrinsic_gas(tx2)
      
      assert gas1 <= gas2
    end
  end
  
  # Helper generators
  defp valid_transaction() do
    gen all nonce <- non_neg_integer(),
            gas_price <- integer(1..1_000_000_000),
            gas_limit <- integer(21_000..10_000_000),
            to <- ethereum_address(),
            value <- wei_amount(),
            data <- binary(max_length: 1000),
            {v, r, s} <- valid_signature() do
      
      %Transaction{
        nonce: nonce,
        gas_price: gas_price, 
        gas_limit: gas_limit,
        to: to,
        value: value,
        data: data,
        v: v,
        r: r,
        s: s
      }
    end
  end
  
  defp valid_signature() do
    gen all r <- integer(1..(secp256k1_order() - 1)),
            s <- integer(1..(secp256k1_order() - 1)),
            recovery_id <- integer(0..3) do
      {27 + recovery_id, r, s}
    end
  end
end
```

### Example 2: EVM Stack Operations

```elixir
defmodule EVM.PropertyTests.StackTest do
  use Blockchain.PropertyTesting.Framework
  
  alias EVM.Stack
  
  property_test "stack operations preserve LIFO order" do
    check all values <- list_of(integer()) do
      # Push all values
      stack = Enum.reduce(values, Stack.new(), fn value, acc ->
        {:ok, new_stack} = Stack.push(acc, value)
        new_stack
      end)
      
      # Pop all values
      {popped_values, empty_stack} = pop_all(stack)
      
      # Should be empty and values in reverse order
      assert Stack.empty?(empty_stack)
      assert popped_values == Enum.reverse(values)
    end
  end
  
  property_test "stack size is correctly maintained" do
    check all operations <- list_of(stack_operation()) do
      final_stack = Enum.reduce(operations, Stack.new(), fn op, stack ->
        apply_stack_operation(op, stack)
      end)
      
      expected_size = calculate_expected_size(operations)
      assert Stack.size(final_stack) == expected_size
    end
  end
  
  property_test "stack overflow is detected" do
    check all extra_values <- list_of(integer(), min_length: 1025) do
      result = Enum.reduce_while(extra_values, Stack.new(), fn value, stack ->
        case Stack.push(stack, value) do
          {:ok, new_stack} -> {:cont, new_stack}
          {:error, :stack_overflow} -> {:halt, :overflow}
        end
      end)
      
      assert result == :overflow
    end
  end
  
  # Helper functions
  defp stack_operation() do
    frequency([
      {3, {:push, integer()}},
      {2, :pop},
      {1, :dup},
      {1, :swap}
    ])
  end
  
  defp apply_stack_operation({:push, value}, stack) do
    case Stack.push(stack, value) do
      {:ok, new_stack} -> new_stack
      {:error, _} -> stack  # Ignore overflow
    end
  end
  
  defp apply_stack_operation(:pop, stack) do
    case Stack.pop(stack) do
      {:ok, {_value, new_stack}} -> new_stack
      {:error, _} -> stack  # Ignore underflow
    end
  end
  
  # ... other operation implementations
end
```

### Example 3: Cryptographic Properties

```elixir
defmodule ExthCrypto.PropertyTests.HashTest do
  use Blockchain.PropertyTesting.Framework
  
  alias ExthCrypto.Hash.Keccak
  
  property_test "keccak256 is deterministic" do
    check all input <- binary() do
      hash1 = Keccak.kec(input)
      hash2 = Keccak.kec(input)
      
      assert hash1 == hash2
      assert byte_size(hash1) == 32
    end
  end
  
  property_test "keccak256 has avalanche effect" do
    check all input <- binary(min_length: 1),
              bit_position <- integer(0..bit_size(input) - 1) do
      
      # Flip one bit
      modified_input = flip_bit(input, bit_position)
      
      original_hash = Keccak.kec(input)
      modified_hash = Keccak.kec(modified_input)
      
      # Hashes should be completely different
      hamming_distance = calculate_hamming_distance(original_hash, modified_hash)
      
      # At least 25% of bits should change (conservative threshold)
      assert hamming_distance >= 64  # 64 out of 256 bits
    end
  end
  
  property_test "different inputs produce different hashes" do
    check all {input1, input2} <- {binary(), binary()},
              input1 != input2 do
      
      hash1 = Keccak.kec(input1)
      hash2 = Keccak.kec(input2)
      
      # Hash collision should be astronomically unlikely
      assert hash1 != hash2
    end
  end
  
  # Utility functions
  defp flip_bit(binary, bit_position) do
    byte_position = div(bit_position, 8)
    bit_in_byte = rem(bit_position, 8)
    
    <<prefix::binary-size(byte_position), byte::8, suffix::binary>> = binary
    flipped_byte = Bitwise.bxor(byte, 1 <<< bit_in_byte)
    
    <<prefix::binary, flipped_byte::8, suffix::binary>>
  end
  
  defp calculate_hamming_distance(<<>>, <<>>), do: 0
  defp calculate_hamming_distance(<<a, rest_a::binary>>, <<b, rest_b::binary>>) do
    byte_distance = Bitwise.bxor(a, b) |> count_set_bits()
    byte_distance + calculate_hamming_distance(rest_a, rest_b)
  end
  
  defp count_set_bits(0), do: 0
  defp count_set_bits(n), do: (n &&& 1) + count_set_bits(n >>> 1)
end
```

## Conclusion

The property-based testing framework provides comprehensive testing capabilities for the Mana-Ethereum client, including:

- **Comprehensive Coverage**: Tests transaction processing, EVM execution, cryptographic operations, and P2P networking
- **Advanced Fuzzing**: Intensive stress testing to discover edge cases and security vulnerabilities  
- **Professional Reporting**: Multiple report formats with detailed analysis and visualizations
- **CI/CD Integration**: Automated testing with GitHub Actions workflows and artifact management
- **Performance Analysis**: Benchmarking and performance regression detection

By following the practices and examples in this guide, you can effectively use and extend the property-based testing framework to improve the reliability and robustness of the Mana-Ethereum implementation.

For additional support or questions, please refer to the codebase documentation or create an issue in the project repository.