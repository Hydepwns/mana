# GenServer Refactoring Guide for Idiomatic Elixir

## Overview
This guide documents best practices and patterns for refactoring GenServers to be perfectly idiomatic Elixir code.

## Key Principles

### 1. State Management
**❌ Bad: Using plain maps for state**
```elixir
def init(_) do
  {:ok, %{counter: 0, buffer: []}}
end
```

**✅ Good: Using structs with clear types**
```elixir
defmodule State do
  defstruct counter: 0, buffer: [], config: %{}
  @type t :: %__MODULE__{
    counter: non_neg_integer(),
    buffer: list(),
    config: map()
  }
end

def init(_) do
  {:ok, %State{}}
end
```

### 2. Pattern Matching in Callbacks

**❌ Bad: Conditional logic in handlers**
```elixir
def handle_call(request, _from, state) do
  case request do
    :get_state -> {:reply, state, state}
    {:add, value} -> {:reply, :ok, %{state | counter: state.counter + value}}
    _ -> {:reply, :error, state}
  end
end
```

**✅ Good: Multiple function clauses with pattern matching**
```elixir
def handle_call(:get_state, _from, state) do
  {:reply, state, state}
end

def handle_call({:add, value}, _from, state) when is_integer(value) do
  {:reply, :ok, %{state | counter: state.counter + value}}
end

def handle_call(_request, _from, state) do
  {:reply, {:error, :unknown_request}, state}
end
```

### 3. Timeout Management

**❌ Bad: Hardcoded timeouts in GenServer.call**
```elixir
def get_data(server) do
  GenServer.call(server, :get_data, 5000)
end
```

**✅ Good: Using Common.GenServerUtils**
```elixir
def get_data(server) do
  Common.GenServerUtils.call(server, :get_data,
    timeout: timeout_for(:get_data),
    circuit_breaker: :my_breaker,
    telemetry_metadata: %{operation: :get_data}
  )
end
```

### 4. Error Handling

**❌ Bad: Letting processes crash without context**
```elixir
def handle_call({:process, data}, _from, state) do
  result = dangerous_operation(data)  # May crash
  {:reply, result, state}
end
```

**✅ Good: Explicit error handling with telemetry**
```elixir
def handle_call({:process, data}, _from, state) do
  case safe_process(data) do
    {:ok, result} ->
      emit_telemetry(:success, %{operation: :process})
      {:reply, {:ok, result}, state}
    
    {:error, reason} = error ->
      emit_telemetry(:error, %{operation: :process, reason: reason})
      Logger.error("Processing failed", reason: reason, data: data)
      {:reply, error, state}
  end
end
```

### 5. Async Operations

**❌ Bad: Blocking operations in handle_call**
```elixir
def handle_call(:sync_data, _from, state) do
  # This blocks the GenServer
  data = fetch_from_external_api()
  {:reply, data, state}
end
```

**✅ Good: Use handle_continue or async tasks**
```elixir
def handle_call(:sync_data, from, state) do
  {:noreply, state, {:continue, {:fetch_data, from}}}
end

def handle_continue({:fetch_data, from}, state) do
  # Spawn task for async operation
  Task.async(fn -> fetch_from_external_api() end)
  {:noreply, %{state | pending: from}}
end

def handle_info({ref, result}, state) when is_reference(ref) do
  GenServer.reply(state.pending, result)
  {:noreply, %{state | pending: nil}}
end
```

### 6. Process Lifecycle

**✅ Good: Proper initialization and cleanup**
```elixir
def init(args) do
  Process.flag(:trap_exit, true)  # For proper cleanup
  
  # Schedule periodic tasks
  schedule_cleanup()
  
  # Initialize with telemetry
  emit_telemetry(:init, %{}, %{args: args})
  
  {:ok, initial_state(args)}
end

def terminate(reason, state) do
  # Clean up resources
  cleanup_resources(state)
  
  # Log termination
  Logger.info("Terminating", reason: reason)
  
  # Emit telemetry
  emit_telemetry(:terminate, %{}, %{reason: reason})
  
  :ok
end
```

### 7. Supervision Integration

**✅ Good: Proper child_spec**
```elixir
def child_spec(args) do
  %{
    id: __MODULE__,
    start: {__MODULE__, :start_link, [args]},
    restart: :permanent,  # or :transient, :temporary
    shutdown: 5_000,       # milliseconds to wait for termination
    type: :worker
  }
end
```

## Common Patterns

### 1. The Registry Pattern
```elixir
defmodule MyApp.WorkerRegistry do
  use GenServer
  
  defmodule State do
    defstruct workers: %{}, monitors: %{}
  end
  
  def register(name, pid) do
    GenServer.call(__MODULE__, {:register, name, pid})
  end
  
  def handle_call({:register, name, pid}, _from, state) do
    ref = Process.monitor(pid)
    
    new_state = state
      |> put_in([:workers, name], pid)
      |> put_in([:monitors, ref], name)
    
    {:reply, :ok, new_state}
  end
  
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {name, monitors} = Map.pop(state.monitors, ref)
    workers = Map.delete(state.workers, name)
    
    {:noreply, %{state | workers: workers, monitors: monitors}}
  end
end
```

### 2. The Buffer Pattern
```elixir
defmodule MyApp.BufferedWriter do
  use GenServer
  
  @buffer_size 100
  @flush_interval 5_000
  
  defmodule State do
    defstruct buffer: [], buffer_size: 0
  end
  
  def init(_) do
    schedule_flush()
    {:ok, %State{}}
  end
  
  def handle_cast({:write, data}, state) do
    new_state = add_to_buffer(state, data)
    
    if new_state.buffer_size >= @buffer_size do
      flush_buffer(new_state)
    else
      {:noreply, new_state}
    end
  end
  
  def handle_info(:flush, state) do
    schedule_flush()
    flush_buffer(state)
  end
  
  defp flush_buffer(%State{buffer: []} = state) do
    {:noreply, state}
  end
  
  defp flush_buffer(state) do
    # Write buffer to storage
    write_batch(Enum.reverse(state.buffer))
    {:noreply, %State{}}
  end
end
```

### 3. The Circuit Breaker Integration Pattern
```elixir
defmodule MyApp.ResilientService do
  use Common.GenServerPatterns,
    telemetry_prefix: [:my_app, :service]
  
  defstate do
    field :circuit_breaker, atom(), default: :service_breaker
  end
  
  defcall {:request, data} do
    with_circuit_breaker state.circuit_breaker do
      case make_external_request(data) do
        {:ok, response} ->
          {:reply, {:ok, response}, state}
        
        {:error, _} = error ->
          {:reply, error, state}
      end
    end
  end
  
  defp with_circuit_breaker(breaker, fun) do
    case ExWire.CircuitBreaker.call(breaker, fun) do
      {:ok, result} -> result
      {:error, :circuit_open} -> {:reply, {:error, :service_unavailable}, state}
    end
  end
end
```

## Refactoring Checklist

### Phase 1: Structure
- [ ] Convert map-based state to struct
- [ ] Add @type specifications
- [ ] Define clear API functions
- [ ] Separate client API from server callbacks

### Phase 2: Pattern Matching
- [ ] Replace case statements with function clauses
- [ ] Add guards for input validation
- [ ] Use pattern matching in function heads
- [ ] Handle edge cases explicitly

### Phase 3: Error Handling
- [ ] Wrap dangerous operations in try/catch or with
- [ ] Add telemetry events
- [ ] Log errors with context
- [ ] Return tagged tuples

### Phase 4: Performance
- [ ] Add hibernation for idle processes
- [ ] Use handle_continue for async work
- [ ] Implement proper backpressure
- [ ] Add circuit breakers for external calls

### Phase 5: Observability
- [ ] Add telemetry events
- [ ] Include process metadata
- [ ] Track key metrics
- [ ] Add introspection functions

## Migration Example

### Before (Anti-patterns):
```elixir
defmodule OldServer do
  use GenServer
  
  def init(_) do
    {:ok, %{data: [], count: 0}}
  end
  
  def handle_call(msg, _from, state) do
    case msg do
      :get -> 
        {:reply, state.data, state}
      {:add, item} ->
        new_state = %{state | data: [item | state.data], count: state.count + 1}
        {:reply, :ok, new_state}
    end
  end
end
```

### After (Idiomatic):
```elixir
defmodule NewServer do
  use Common.GenServerPatterns
  
  defstate do
    field :data, list(), default: []
    field :count, non_neg_integer(), default: 0
  end
  
  def init_state(_args) do
    %State{}
  end
  
  # Clear API
  def get_data(server \\ __MODULE__) do
    Common.GenServerUtils.quick_call(server, :get_data)
  end
  
  def add_item(item, server \\ __MODULE__) do
    Common.GenServerUtils.call(server, {:add_item, item})
  end
  
  # Pattern-matched handlers
  defcall :get_data do
    {:reply, state.data, state}
  end
  
  defcall {:add_item, item} when not is_nil(item) do
    new_state = state
      |> update_in([:data], &[item | &1])
      |> update_in([:count], &(&1 + 1))
    
    {:reply, :ok, new_state}
  end
end
```

## Files to Refactor

High-priority GenServers that need refactoring:
1. `/apps/ex_wire/lib/ex_wire/sync.ex` - Complex state management
2. `/apps/jsonrpc2/lib/jsonrpc2/subscription_manager.ex` - Event handling
3. `/apps/ex_wire/lib/ex_wire/consensus/*.ex` - Distributed consensus
4. `/apps/ex_wire/lib/ex_wire/enterprise/*.ex` - Enterprise features
5. `/apps/blockchain/lib/blockchain/transaction_pool.ex` - Already started with V2

## Testing Patterns

```elixir
defmodule MyServerTest do
  use ExUnit.Case
  
  setup do
    {:ok, pid} = MyServer.start_link()
    {:ok, server: pid}
  end
  
  describe "state management" do
    test "initializes with default state", %{server: server} do
      assert %State{data: [], count: 0} = MyServer.get_state(server)
    end
    
    test "adds items correctly", %{server: server} do
      assert :ok = MyServer.add_item("test", server)
      assert %State{data: ["test"], count: 1} = MyServer.get_state(server)
    end
  end
  
  describe "error handling" do
    test "handles invalid input", %{server: server} do
      assert {:error, :invalid_input} = MyServer.add_item(nil, server)
    end
  end
end
```

## Next Steps

1. **Immediate**: Refactor critical GenServers (TransactionPool, Sync)
2. **Short-term**: Apply patterns to all consensus modules
3. **Long-term**: Create code generation macros for common patterns
4. **Continuous**: Monitor telemetry and optimize based on metrics

## Resources

- [GenServer Best Practices](https://hexdocs.pm/elixir/GenServer.html)
- [Common.GenServerPatterns module](/apps/common/lib/common/genserver_patterns.ex)
- [Common.GenServerUtils module](/apps/common/lib/common/genserver_utils.ex)
- [TransactionPoolV2 example](/apps/blockchain/lib/blockchain/transaction_pool_v2.ex)