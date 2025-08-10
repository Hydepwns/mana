# CI Recovery Plan for Mana Repository

## Current Status
After multiple iterations of fixes, the CI pipeline is still failing. However, we've made significant progress:

### ✅ Issues Fixed
1. **Broken badges** - Updated to point to correct repository (Hydepwns/mana)
2. **Language detection** - Fixed GitHub showing repo as HTML (was 83.5% HTML due to Rust docs)
3. **Invalid syntax** - Fixed `while` loop in mainnet_integration.ex  
4. **Dependency issues** - Vendored and patched mix_erlang_tasks dependency
5. **Property test imports** - Added missing `use ExUnit.Case` to property test modules
6. **CI workflow syntax** - Removed broken `--dot-formatter` flag

### ❌ Remaining Issues
The CI is still failing during test compilation with numerous warnings and typing violations.

## Root Cause Analysis

### 1. **Deprecated Function Calls**
- Multiple uses of `Logger.warn/1` (should be `Logger.warning/2`)
- Use of deprecated Elixir/Erlang functions throughout dependencies
- Stream of deprecation warnings from dependencies (decimal, toml, etc.)

### 2. **Typing Violations (Dialyzer)**
The codebase has extensive typing issues detected by dialyzer:
- Functions with clauses that will never match
- Undefined or private functions being called
- Type mismatches in function returns
- Missing function implementations (e.g., GenServer callbacks)

### 3. **Undefined/Missing Modules**
- `Blockchain.PropertyTesting.Framework` - missing module referenced in tests
- `Blockchain.PropertyTesting.Properties` - missing module referenced in tests
- Various undefined functions being called across modules

### 4. **Test Compilation Failures**
Tests fail to compile due to:
- Missing property test framework modules
- Typing violations preventing compilation
- Missing function implementations

## Recommended Recovery Steps

### Phase 1: Stabilize Compilation (Priority: HIGH)
```bash
# 1. Disable property tests temporarily
mkdir -p test_disabled
mv apps/*/test/**/property_tests test_disabled/

# 2. Fix Logger deprecation warnings globally
find . -name "*.ex" -type f -exec sed -i 's/Logger\.warn(/Logger.warning(/g' {} \;

# 3. Update mix.exs to reduce compilation strictness
# In each app's mix.exs, temporarily set:
# elixirc_options: [warnings_as_errors: false]
```

### Phase 2: Fix Critical Issues (Priority: HIGH)
```elixir
# 1. Create missing test framework modules
# Create: apps/blockchain/test/support/property_testing_framework.ex
defmodule Blockchain.PropertyTesting.Framework do
  defmacro __using__(_opts) do
    quote do
      use ExUnit.Case, async: true
      use ExUnitProperties
      import StreamData
    end
  end
end

# 2. Create: apps/blockchain/test/support/property_testing_properties.ex
defmodule Blockchain.PropertyTesting.Properties do
  # Add common property testing helpers here
end
```

### Phase 3: Address Typing Issues (Priority: MEDIUM)
```bash
# 1. Run dialyzer locally to get full list
mix dialyzer

# 2. Create a dialyzer ignore file
echo "lib/ex_wire/sync/fast_sync.ex:304" >> .dialyzer_ignore
# Add other problematic lines

# 3. Fix undefined function calls one by one
# Start with the most critical modules
```

### Phase 4: Update Dependencies (Priority: MEDIUM)
```elixir
# In mix.exs, update problematic dependencies:
{:decimal, "~> 2.0"},  # Update from 1.5.0
{:stream_data, "~> 1.0"},  # Update from 0.6.0
{:prometheus, "~> 5.0"},  # Currently using retired 4.13.0
```

### Phase 5: Progressive CI Re-enablement (Priority: LOW)
```yaml
# .github/workflows/ci.yml
# Add a matrix strategy to test components separately:
strategy:
  matrix:
    app: [blockchain, ex_wire, exth_crypto, merkle_patricia_tree]
  continue-on-error: true  # Allow partial failures initially
```

## Quick Wins (Can be done immediately)

### 1. Create a minimal CI that just compiles
```yaml
# .github/workflows/compile-only.yml
name: Compile Check
on: [push, pull_request]
jobs:
  compile:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.18.4'
        otp-version: '27.2'
    - run: mix deps.get
    - run: mix compile --warnings-as-errors=false
```

### 2. Disable strict compilation temporarily
```elixir
# In root mix.exs
def project do
  [
    # ...
    elixirc_options: [warnings_as_errors: false],  # Temporarily disable
    # ...
  ]
end
```

### 3. Create test helper to skip broken tests
```elixir
# test/test_helper.exs
ExUnit.configure(exclude: [:property_test, :network])
ExUnit.start()
```

## Long-term Solutions

1. **Gradual type annotation improvement**
   - Add @spec annotations to all public functions
   - Fix dialyzer warnings module by module

2. **Dependency modernization**
   - Update to latest stable versions
   - Replace deprecated function calls

3. **Test infrastructure rebuild**
   - Properly implement property testing framework
   - Add integration test suite with proper mocking

4. **CI/CD pipeline redesign**
   - Separate compilation, test, and analysis jobs
   - Add caching for compiled dependencies
   - Implement gradual rollout with feature flags

## Monitoring Progress

Track CI recovery with these metrics:
- Compilation warnings count (currently: 100+)
- Dialyzer warnings count (currently: 50+)
- Test pass rate (currently: 0% - doesn't compile)
- CI execution time (target: < 5 minutes)

## Emergency Bypass

If you need to push code urgently while CI is being fixed:
```bash
# Create a temporary branch that bypasses CI
git checkout -b ci-bypass-temp
# Make your changes
git push origin ci-bypass-temp
# Create PR with [skip ci] in the title
```

## Resources

- [Elixir 1.18 Deprecations](https://hexdocs.pm/elixir/changelog.html)
- [Dialyzer Documentation](https://www.erlang.org/doc/man/dialyzer.html)
- [ExUnit Property Testing](https://hexdocs.pm/stream_data/ExUnitProperties.html)

## Conclusion

The CI issues are extensive but solvable. The recommended approach is:
1. **Immediately**: Disable strict compilation to get a green build
2. **This week**: Fix critical undefined functions and modules
3. **This month**: Address typing violations and deprecation warnings
4. **Long-term**: Modernize the entire test infrastructure

The codebase appears to be in a transitional state with many partially-implemented features (HSM, Layer 2, Verkle trees). Focus on stabilizing the core functionality first before addressing these advanced features.