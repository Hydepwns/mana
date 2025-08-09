defmodule MerklePatriciaTree.DB.AntiodoteCRDTs do
  @moduledoc """
  Custom CRDT implementations for Ethereum blockchain data structures.
  
  These CRDTs ensure eventual consistency and automatic conflict resolution
  for distributed blockchain state management.
  """

  defmodule AccountBalance do
    @moduledoc """
    State-based CRDT for Ethereum account balances.
    
    Uses a combination of:
    - PN-Counter for balance tracking
    - LWW-Register for nonce values
    - OR-Set for transaction history references
    """

    defstruct [
      :address,
      :balance_counter,
      :nonce_register,
      :tx_history,
      :vector_clock,
      :last_modified
    ]

    @type t :: %__MODULE__{
      address: binary(),
      balance_counter: {non_neg_integer(), non_neg_integer()},  # {increments, decrements}
      nonce_register: {non_neg_integer(), non_neg_integer()},    # {nonce, timestamp}
      tx_history: MapSet.t(),
      vector_clock: map(),
      last_modified: non_neg_integer()
    }

    @doc """
    Creates a new account balance CRDT.
    """
    def new(address) do
      %__MODULE__{
        address: address,
        balance_counter: {0, 0},
        nonce_register: {0, timestamp()},
        tx_history: MapSet.new(),
        vector_clock: %{},
        last_modified: timestamp()
      }
    end

    @doc """
    Credits the account (increases balance).
    """
    def credit(%__MODULE__{} = account, amount, node_id) do
      {inc, dec} = account.balance_counter
      %{account |
        balance_counter: {inc + amount, dec},
        vector_clock: increment_clock(account.vector_clock, node_id),
        last_modified: timestamp()
      }
    end

    @doc """
    Debits the account (decreases balance).
    """
    def debit(%__MODULE__{} = account, amount, node_id) do
      {inc, dec} = account.balance_counter
      %{account |
        balance_counter: {inc, dec + amount},
        vector_clock: increment_clock(account.vector_clock, node_id),
        last_modified: timestamp()
      }
    end

    @doc """
    Updates the nonce (using Last-Write-Wins).
    """
    def update_nonce(%__MODULE__{} = account, new_nonce, node_id) do
      {_old_nonce, old_timestamp} = account.nonce_register
      now = timestamp()
      
      if now > old_timestamp do
        %{account |
          nonce_register: {new_nonce, now},
          vector_clock: increment_clock(account.vector_clock, node_id),
          last_modified: now
        }
      else
        account
      end
    end

    @doc """
    Adds a transaction to the history.
    """
    def add_transaction(%__MODULE__{} = account, tx_hash, node_id) do
      %{account |
        tx_history: MapSet.put(account.tx_history, tx_hash),
        vector_clock: increment_clock(account.vector_clock, node_id),
        last_modified: timestamp()
      }
    end

    @doc """
    Merges two account CRDTs (commutative, associative, idempotent).
    """
    def merge(%__MODULE__{} = a, %__MODULE__{} = b) do
      # Merge balance counters (PN-Counter merge)
      {a_inc, a_dec} = a.balance_counter
      {b_inc, b_dec} = b.balance_counter
      merged_balance = {max(a_inc, b_inc), max(a_dec, b_dec)}
      
      # Merge nonce (LWW-Register merge)
      {a_nonce, a_time} = a.nonce_register
      {b_nonce, b_time} = b.nonce_register
      merged_nonce = if a_time >= b_time, do: {a_nonce, a_time}, else: {b_nonce, b_time}
      
      # Merge transaction history (OR-Set merge)
      merged_history = MapSet.union(a.tx_history, b.tx_history)
      
      # Merge vector clocks
      merged_clock = merge_clocks(a.vector_clock, b.vector_clock)
      
      %__MODULE__{
        address: a.address,
        balance_counter: merged_balance,
        nonce_register: merged_nonce,
        tx_history: merged_history,
        vector_clock: merged_clock,
        last_modified: max(a.last_modified, b.last_modified)
      }
    end

    @doc """
    Gets the current balance value.
    """
    def get_balance(%__MODULE__{balance_counter: {inc, dec}}) do
      inc - dec
    end

    @doc """
    Gets the current nonce value.
    """
    def get_nonce(%__MODULE__{nonce_register: {nonce, _}}) do
      nonce
    end

    defp timestamp do
      System.system_time(:millisecond)
    end

    defp increment_clock(clock, node_id) do
      Map.update(clock, node_id, 1, &(&1 + 1))
    end

    defp merge_clocks(clock_a, clock_b) do
      Map.merge(clock_a, clock_b, fn _k, v1, v2 -> max(v1, v2) end)
    end
  end

  defmodule TransactionPool do
    @moduledoc """
    Operation-based CRDT for the transaction pool.
    
    Uses an OR-Set with causal ordering to ensure all nodes
    eventually have the same set of pending transactions.
    """

    defstruct [
      :transactions,
      :tombstones,
      :vector_clock,
      :last_gc
    ]

    @type t :: %__MODULE__{
      transactions: map(),  # tx_hash => {tx_data, unique_id, timestamp}
      tombstones: MapSet.t(),  # removed transaction identifiers
      vector_clock: map(),
      last_gc: non_neg_integer()
    }

    @doc """
    Creates a new transaction pool CRDT.
    """
    def new do
      %__MODULE__{
        transactions: %{},
        tombstones: MapSet.new(),
        vector_clock: %{},
        last_gc: timestamp()
      }
    end

    @doc """
    Adds a transaction to the pool.
    """
    def add_transaction(%__MODULE__{} = pool, tx_hash, tx_data, node_id) do
      unique_id = generate_unique_id(node_id)
      
      if not tombstone_exists?(pool, tx_hash, unique_id) do
        %{pool |
          transactions: Map.put(pool.transactions, tx_hash, {tx_data, unique_id, timestamp()}),
          vector_clock: increment_clock(pool.vector_clock, node_id)
        }
      else
        pool
      end
    end

    @doc """
    Removes a transaction from the pool.
    """
    def remove_transaction(%__MODULE__{} = pool, tx_hash, node_id) do
      case Map.get(pool.transactions, tx_hash) do
        {_tx_data, unique_id, _timestamp} ->
          %{pool |
            transactions: Map.delete(pool.transactions, tx_hash),
            tombstones: MapSet.put(pool.tombstones, {tx_hash, unique_id}),
            vector_clock: increment_clock(pool.vector_clock, node_id)
          }
        
        nil ->
          pool
      end
    end

    @doc """
    Merges two transaction pool CRDTs.
    """
    def merge(%__MODULE__{} = a, %__MODULE__{} = b) do
      # Merge tombstones first
      merged_tombstones = MapSet.union(a.tombstones, b.tombstones)
      
      # Merge transactions, filtering out tombstoned ones
      merged_transactions = 
        Map.merge(a.transactions, b.transactions, fn _tx_hash, 
          {_, a_id, a_time} = a_entry,
          {_, b_id, b_time} = b_entry ->
          # Keep the entry with the latest timestamp
          if a_time >= b_time, do: a_entry, else: b_entry
        end)
        |> Enum.filter(fn {tx_hash, {_, unique_id, _}} ->
          not MapSet.member?(merged_tombstones, {tx_hash, unique_id})
        end)
        |> Map.new()
      
      # Merge vector clocks
      merged_clock = merge_clocks(a.vector_clock, b.vector_clock)
      
      # Perform garbage collection if needed
      pool = %__MODULE__{
        transactions: merged_transactions,
        tombstones: merged_tombstones,
        vector_clock: merged_clock,
        last_gc: max(a.last_gc, b.last_gc)
      }
      
      maybe_garbage_collect(pool)
    end

    @doc """
    Gets all current transactions in the pool.
    """
    def get_transactions(%__MODULE__{transactions: txs}) do
      Map.new(txs, fn {hash, {data, _, _}} -> {hash, data} end)
    end

    defp tombstone_exists?(pool, tx_hash, unique_id) do
      MapSet.member?(pool.tombstones, {tx_hash, unique_id})
    end

    defp generate_unique_id(node_id) do
      "#{node_id}_#{System.unique_integer([:positive, :monotonic])}_#{timestamp()}"
    end

    defp maybe_garbage_collect(%__MODULE__{last_gc: last_gc} = pool) do
      now = timestamp()
      gc_interval = 3600_000  # 1 hour
      
      if now - last_gc > gc_interval do
        # Remove old tombstones (older than 24 hours)
        cutoff = now - 86400_000
        
        cleaned_tombstones = 
          pool.tombstones
          |> Enum.filter(fn {_tx_hash, unique_id} ->
            case String.split(unique_id, "_") do
              [_, _, timestamp_str] ->
                String.to_integer(timestamp_str) > cutoff
              _ ->
                true
            end
          end)
          |> MapSet.new()
        
        %{pool | tombstones: cleaned_tombstones, last_gc: now}
      else
        pool
      end
    end

    defp timestamp do
      System.system_time(:millisecond)
    end

    defp increment_clock(clock, node_id) do
      Map.update(clock, node_id, 1, &(&1 + 1))
    end

    defp merge_clocks(clock_a, clock_b) do
      Map.merge(clock_a, clock_b, fn _k, v1, v2 -> max(v1, v2) end)
    end
  end

  defmodule StateTree do
    @moduledoc """
    Merkle-CRDT for distributed state tree synchronization.
    
    Combines Merkle tree properties with CRDT semantics for
    efficient state synchronization across nodes.
    """

    defstruct [
      :root_hash,
      :nodes,
      :pending_updates,
      :vector_clock,
      :last_sync
    ]

    @type t :: %__MODULE__{
      root_hash: binary(),
      nodes: map(),  # path => {node_hash, node_data, version}
      pending_updates: list(),
      vector_clock: map(),
      last_sync: non_neg_integer()
    }

    @doc """
    Creates a new state tree CRDT.
    """
    def new(root_hash \\ <<0::256>>) do
      %__MODULE__{
        root_hash: root_hash,
        nodes: %{},
        pending_updates: [],
        vector_clock: %{},
        last_sync: timestamp()
      }
    end

    @doc """
    Updates a node in the tree.
    """
    def update_node(%__MODULE__{} = tree, path, node_hash, node_data, node_id) do
      version = get_next_version(tree.vector_clock, node_id)
      
      updated_nodes = Map.update(
        tree.nodes,
        path,
        {node_hash, node_data, version},
        fn {_old_hash, _old_data, old_version} = old_entry ->
          if version > old_version do
            {node_hash, node_data, version}
          else
            old_entry
          end
        end
      )
      
      %{tree |
        nodes: updated_nodes,
        pending_updates: [{path, node_hash, timestamp()} | tree.pending_updates],
        vector_clock: increment_clock(tree.vector_clock, node_id)
      }
    end

    @doc """
    Merges two state tree CRDTs.
    """
    def merge(%__MODULE__{} = a, %__MODULE__{} = b) do
      # Merge nodes using version comparison
      merged_nodes = Map.merge(a.nodes, b.nodes, fn _path,
        {_, _, a_version} = a_node,
        {_, _, b_version} = b_node ->
        if a_version >= b_version, do: a_node, else: b_node
      end)
      
      # Merge pending updates
      merged_updates = 
        (a.pending_updates ++ b.pending_updates)
        |> Enum.uniq_by(fn {path, _, _} -> path end)
        |> Enum.take(1000)  # Limit pending updates
      
      # Merge vector clocks
      merged_clock = merge_clocks(a.vector_clock, b.vector_clock)
      
      # Recalculate root hash
      new_root = calculate_root_hash(merged_nodes)
      
      %__MODULE__{
        root_hash: new_root,
        nodes: merged_nodes,
        pending_updates: merged_updates,
        vector_clock: merged_clock,
        last_sync: max(a.last_sync, b.last_sync)
      }
    end

    @doc """
    Gets nodes that need synchronization.
    """
    def get_sync_candidates(%__MODULE__{pending_updates: updates}, max_candidates \\ 100) do
      updates
      |> Enum.take(max_candidates)
      |> Enum.map(fn {path, _, _} -> path end)
    end

    defp get_next_version(clock, node_id) do
      Map.get(clock, node_id, 0) + 1
    end

    defp calculate_root_hash(nodes) do
      # Simplified root hash calculation
      nodes
      |> Map.values()
      |> Enum.map(fn {hash, _, _} -> hash end)
      |> Enum.reduce(<<0::256>>, fn hash, acc ->
        :crypto.hash(:sha256, acc <> hash)
      end)
    end

    defp timestamp do
      System.system_time(:millisecond)
    end

    defp increment_clock(clock, node_id) do
      Map.update(clock, node_id, 1, &(&1 + 1))
    end

    defp merge_clocks(clock_a, clock_b) do
      Map.merge(clock_a, clock_b, fn _k, v1, v2 -> max(v1, v2) end)
    end
  end
end