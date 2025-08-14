defmodule Blockchain.TransactionPoolFunctional do
  @moduledoc """
  Functional refactoring of TransactionPool with DRY principles.
  
  Key improvements:
  - Pure functions for all business logic
  - Composable validators
  - Pipeline-based transformations
  - Immutable state updates
  - Higher-order functions for common patterns
  """

  use GenServer
  require Logger
  
  import Common.Functional
  import Common.Validation
  alias Common.Production.TransactionPriorityQueue

  # Functional state transformations
  defmodule State do
    @moduledoc false
    
    defstruct [
      :transactions,
      :by_address,
      :by_gas_price,
      :priority_queue,
      :validation_cache,
      :stats,
      :performance_metrics,
      :config
    ]

    @default_config %{
      max_pool_size: 50_000,
      max_transaction_size: 128 * 1024,
      min_gas_price: 1_000_000_000,
      cleanup_interval: 30_000,
      max_transaction_age: 1_800,
      batch_processing_size: 100,
      cache_ttl: 300
    }

    @doc "Pure function to create initial state"
    def new(config \\ %{}) do
      %__MODULE__{
        transactions: %{},
        by_address: %{},
        by_gas_price: [],
        priority_queue: TransactionPriorityQueue.new(max_size: config[:max_pool_size] || 50_000),
        validation_cache: :ets.new(:tx_validation_cache, [:set, :public]),
        stats: initial_stats(),
        performance_metrics: initial_metrics(),
        config: Map.merge(@default_config, config)
      }
    end

    defp initial_stats do
      %{
        total_added: 0,
        total_removed: 0,
        total_rejected: 0,
        validation_cache_hits: 0,
        validation_cache_misses: 0
      }
    end

    defp initial_metrics do
      %{
        add_transaction: [],
        get_pending: [],
        remove_transactions: [],
        cleanup: []
      }
    end
  end

  # Pure functional validators using composition
  defmodule Validators do
    @moduledoc false
    
    import Common.Validation
    import Common.Functional

    @min_gas_price 1_000_000_000
    @max_gas_limit 8_000_000
    @min_gas_limit 21_000

    def transaction_validator do
      all_of([
        gas_validator(),
        nonce_validator(),
        signature_validator(),
        size_validator()
      ])
    end

    def gas_validator do
      fn tx ->
        chain_results({:ok, tx}, [
          &validate_gas_price/1,
          &validate_gas_limit/1,
          &validate_intrinsic_gas/1
        ])
      end
    end

    defp validate_gas_price(tx) do
      validate_range(tx.gas_price, @min_gas_price, :infinity)
      |> map_ok(fn _ -> tx end)
    end

    defp validate_gas_limit(tx) do
      validate_range(tx.gas_limit, @min_gas_limit, @max_gas_limit)
      |> map_ok(fn _ -> tx end)
    end

    defp validate_intrinsic_gas(tx) do
      intrinsic = calculate_intrinsic_gas(tx)
      
      if tx.gas_limit >= intrinsic do
        {:ok, tx}
      else
        {:error, "Gas limit below intrinsic gas: #{intrinsic}"}
      end
    end

    def nonce_validator do
      validator(&(&1.nonce >= 0), "Invalid nonce")
    end

    def signature_validator do
      fn tx ->
        validate_all(tx, [
          validator(&(&1.v > 0), "Invalid v value"),
          validator(&(&1.r > 0), "Invalid r value"),  
          validator(&(&1.s > 0), "Invalid s value")
        ])
      end
    end

    def size_validator(max_size \\ 128 * 1024) do
      fn tx ->
        size = :erlang.external_size(tx)
        if size <= max_size do
          {:ok, tx}
        else
          {:error, "Transaction too large: #{size} bytes"}
        end
      end
    end

    defp calculate_intrinsic_gas(tx) do
      base_gas = 21_000
      data_gas = if tx.data, do: byte_size(tx.data) * 16, else: 0
      base_gas + data_gas
    end
  end

  # Functional transaction operations
  defmodule Operations do
    @moduledoc false
    
    import Common.Functional

    @doc "Pure function to add transaction to state"
    def add_transaction(state, tx, validators \\ [Validators.transaction_validator()]) do
      with {:ok, validated_tx} <- validate_all(tx, validators),
           {:ok, _} <- check_duplicate(state, validated_tx),
           {:ok, _} <- check_capacity(state) do
        
        new_state = state
        |> update_transactions(validated_tx)
        |> update_indices(validated_tx)
        |> update_stats(:added)
        
        {:ok, new_state}
      end
    end

    @doc "Pure function to remove transactions"
    def remove_transactions(state, tx_hashes) do
      tx_hashes
      |> Enum.reduce(state, &remove_single_transaction(&2, &1))
      |> update_stats(:removed, length(tx_hashes))
    end

    defp remove_single_transaction(state, tx_hash) do
      case Map.get(state.transactions, tx_hash) do
        nil -> state
        tx ->
          state
          |> update_in([:transactions], &Map.delete(&1, tx_hash))
          |> update_in([:by_address, tx.from], &List.delete(&1, tx_hash))
          |> rebuild_gas_index()
      end
    end

    @doc "Get pending transactions using functional filters"
    def get_pending(state, limit \\ 100) do
      state.transactions
      |> Map.values()
      |> Enum.sort_by(&(-&1.gas_price))
      |> Enum.take(limit)
    end

    @doc "Pure function for cleanup"
    def cleanup_old_transactions(state, max_age_seconds) do
      current_time = System.system_time(:second)
      cutoff_time = current_time - max_age_seconds
      
      {_keep, remove} = state.transactions
      |> Map.values()
      |> Enum.split_with(&(&1.timestamp > cutoff_time))
      
      remove_hashes = Enum.map(remove, & &1.hash)
      
      state
      |> remove_transactions(remove_hashes)
      |> Map.put(:last_cleanup, current_time)
    end

    defp check_duplicate(state, tx) do
      if Map.has_key?(state.transactions, tx.hash) do
        {:error, "Duplicate transaction"}
      else
        {:ok, tx}
      end
    end

    defp check_capacity(state) do
      if map_size(state.transactions) >= state.config.max_pool_size do
        {:error, "Pool at capacity"}
      else
        {:ok, :space_available}
      end
    end

    defp update_transactions(state, tx) do
      update_in(state.transactions, &Map.put(&1, tx.hash, tx))
    end

    defp update_indices(state, tx) do
      state
      |> update_in([:by_address, tx.from], &[tx.hash | (&1 || [])])
      |> update_gas_price_index(tx)
    end

    defp update_gas_price_index(state, tx) do
      updated_index = [{tx.gas_price, tx.hash} | state.by_gas_price]
      |> Enum.sort_by(&elem(&1, 0), &>=/2)
      |> Enum.take(10_000) # Keep top 10k for performance
      
      %{state | by_gas_price: updated_index}
    end

    defp rebuild_gas_index(state) do
      index = state.transactions
      |> Map.values()
      |> Enum.map(&{&1.gas_price, &1.hash})
      |> Enum.sort_by(&elem(&1, 0), &>=/2)
      
      %{state | by_gas_price: index}
    end

    defp update_stats(state, type, count \\ 1) do
      key = case type do
        :added -> :total_added
        :removed -> :total_removed
        :rejected -> :total_rejected
        _ -> type
      end
      
      update_in(state, [:stats, key], &(&1 + count))
    end
  end

  # Caching layer using functional memoization
  defmodule Cache do
    @moduledoc false
    
    import Common.Functional

    def with_cache(cache_table, key, ttl, compute_fn) do
      case lookup_cache(cache_table, key, ttl) do
        {:hit, value} -> {:cached, value}
        :miss ->
          value = compute_fn.()
          store_cache(cache_table, key, value)
          {:computed, value}
      end
    end

    defp lookup_cache(table, key, ttl) do
      current_time = System.system_time(:second)
      
      case :ets.lookup(table, key) do
        [{^key, value, timestamp}] when timestamp > current_time - ttl ->
          {:hit, value}
        _ ->
          :miss
      end
    end

    defp store_cache(table, key, value) do
      :ets.insert(table, {key, value, System.system_time(:second)})
      value
    end
  end

  # GenServer implementation using functional core
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    state = State.new(opts)
    schedule_cleanup(state.config.cleanup_interval)
    {:ok, state}
  end

  @impl true
  def handle_call({:add_transaction, raw_tx}, _from, state) do
    {result, new_state} = 
      raw_tx
      |> decode_transaction()
      |> flat_map_ok(&Operations.add_transaction(state, &1))
      |> case do
        {:ok, updated_state} -> 
          {{:ok, :added}, updated_state}
        {:error, reason} ->
          {{:error, reason}, update_in(state, [:stats, :total_rejected], &(&1 + 1))}
      end
    
    {:reply, result, new_state}
  end

  @impl true  
  def handle_call({:get_pending, limit}, _from, state) do
    transactions = Operations.get_pending(state, limit)
    {:reply, {:ok, transactions}, state}
  end

  @impl true
  def handle_call({:get_transaction, hash}, _from, state) do
    result = Map.get(state.transactions, hash)
    |> case do
      nil -> {:error, :not_found}
      tx -> {:ok, tx}
    end
    
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:remove_transactions, hashes}, state) do
    new_state = Operations.remove_transactions(state, hashes)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup, _state) do
    new_state = Operations.cleanup_old_transactions(state, state.config.max_transaction_age)
    schedule_cleanup(state.config.cleanup_interval)
    {:noreply, new_state}
  end

  # Helper functions
  defp decode_transaction(raw) when is_binary(raw) do
    safe_apply(fn ->
      binary = if String.starts_with?(raw, "0x") do
        raw |> String.slice(2..-1//1) |> Base.decode16!(case: :mixed)
      else
        raw
      end

      case ExRLP.decode(binary) do
        [nonce, gas_price, gas_limit, to, value, data, v, r, s] ->
          %{
            hash: :crypto.hash(:sha256, binary),
            nonce: :binary.decode_unsigned(nonce),
            gas_price: :binary.decode_unsigned(gas_price),
            gas_limit: :binary.decode_unsigned(gas_limit),
            to: if(to == <<>>, do: nil, else: to),
            from: <<0::160>>, # Would be recovered from signature
            value: :binary.decode_unsigned(value),
            data: data,
            v: :binary.decode_unsigned(v),
            r: :binary.decode_unsigned(r),
            s: :binary.decode_unsigned(s),
            timestamp: System.system_time(:second)
          }
        _ ->
          {:error, "Invalid RLP structure"}
      end
    end)
  end
  
  defp decode_transaction(tx) when is_map(tx), do: {:ok, tx}

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
  end

  # Public API using functional transformations
  def add_transaction(raw_tx), do: GenServer.call(__MODULE__, {:add_transaction, raw_tx})
  def get_pending(limit \\ 100), do: GenServer.call(__MODULE__, {:get_pending, limit})
  def get_transaction(hash), do: GenServer.call(__MODULE__, {:get_transaction, hash})
  def remove_transactions(hashes), do: GenServer.cast(__MODULE__, {:remove_transactions, hashes})
end