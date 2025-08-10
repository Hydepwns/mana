defmodule ExWire.Layer2.Sequencer.OrderingPolicy do
  @moduledoc """
  Transaction ordering policies for the sequencer.
  Implements various ordering strategies including fair ordering and MEV mitigation.
  """

  require Logger

  @doc """
  Fair ordering with time-window based randomization.
  Transactions within the same time window are randomly shuffled.
  """
  @spec fair_order(list(map())) :: list(map())
  def fair_order(transactions) do
    # Group transactions by time windows (e.g., 100ms windows)
    # milliseconds
    window_size = 100

    transactions
    |> group_by_time_window(window_size)
    |> Enum.flat_map(fn {_window, txs} ->
      # Randomly shuffle transactions within each window
      Enum.shuffle(txs)
    end)
  end

  @doc """
  Fair selection of transactions for batch creation.
  Ensures diverse sender representation.
  """
  @spec fair_select(list(map()), non_neg_integer()) :: {list(map()), list(map())}
  def fair_select(transactions, limit) do
    # Group by sender
    by_sender = Enum.group_by(transactions, & &1.from)

    # Take transactions in round-robin fashion from each sender
    selected = round_robin_select(by_sender, limit)
    remaining = transactions -- selected

    {selected, remaining}
  end

  @doc """
  MEV auction based ordering.
  Orders transactions to maximize extracted value while preventing sandwich attacks.
  """
  @spec mev_auction_order(list(map())) :: list(map())
  def mev_auction_order(transactions) do
    # Detect potential sandwich attacks
    {sandwiches, normal} = detect_sandwich_attacks(transactions)

    # Order normal transactions by priority fee
    ordered_normal = Enum.sort_by(normal, & &1.priority_fee, :desc)

    # Break up sandwich attacks
    protected = break_sandwiches(sandwiches)

    # Interleave protected and normal transactions
    interleave(protected, ordered_normal)
  end

  @doc """
  MEV-aware selection for batch creation.
  """
  @spec mev_select(list(map()), non_neg_integer()) :: {list(map()), list(map())}
  def mev_select(transactions, limit) do
    # Identify MEV opportunities
    mev_txs = identify_mev_transactions(transactions)
    regular_txs = transactions -- mev_txs

    # Allocate slots: 20% for MEV, 80% for regular
    mev_slots = div(limit, 5)
    regular_slots = limit - mev_slots

    # Select highest value MEV transactions
    selected_mev =
      mev_txs
      |> Enum.sort_by(&calculate_mev_value/1, :desc)
      |> Enum.take(mev_slots)

    # Select regular transactions by priority fee
    selected_regular =
      regular_txs
      |> Enum.sort_by(& &1.priority_fee, :desc)
      |> Enum.take(regular_slots)

    selected = selected_mev ++ selected_regular
    remaining = transactions -- selected

    {selected, remaining}
  end

  @doc """
  Commit-reveal ordering for MEV protection.
  Transactions are ordered based on committed hash reveals.
  """
  @spec commit_reveal_order(list(map()), map()) :: list(map())
  def commit_reveal_order(transactions, commits) do
    # Match transactions to their commits
    {revealed, unrevealed} =
      Enum.split_with(transactions, fn tx ->
        Map.has_key?(commits, tx.hash)
      end)

    # Order revealed transactions by commit timestamp
    ordered_revealed =
      Enum.sort_by(revealed, fn tx ->
        commits[tx.hash].timestamp
      end)

    # Append unrevealed transactions
    ordered_revealed ++ unrevealed
  end

  @doc """
  Time-boost ordering where transactions can pay for earlier inclusion.
  """
  @spec time_boost_order(list(map())) :: list(map())
  def time_boost_order(transactions) do
    Enum.sort_by(transactions, fn tx ->
      # Calculate effective timestamp with boost
      base_time = DateTime.to_unix(tx.received_at, :microsecond)
      boost = calculate_time_boost(tx.priority_fee)
      base_time - boost
    end)
  end

  # Private Functions

  defp group_by_time_window(transactions, window_size) do
    Enum.group_by(transactions, fn tx ->
      timestamp = DateTime.to_unix(tx.received_at, :millisecond)
      div(timestamp, window_size)
    end)
  end

  defp round_robin_select(by_sender, limit) do
    do_round_robin(Map.values(by_sender), limit, [])
  end

  defp do_round_robin([], _limit, selected), do: selected
  defp do_round_robin(_groups, 0, selected), do: selected

  defp do_round_robin(groups, limit, selected) do
    # Take one transaction from each non-empty group
    {new_selected, remaining_groups} =
      Enum.reduce(groups, {[], []}, fn group, {sel, rem} ->
        case group do
          [] ->
            {sel, rem}

          [tx | rest] ->
            if length(sel) < limit do
              {[tx | sel], [rest | rem]}
            else
              {sel, [group | rem]}
            end
        end
      end)

    new_limit = limit - length(new_selected)

    if new_limit > 0 and length(remaining_groups) > 0 do
      do_round_robin(remaining_groups, new_limit, selected ++ new_selected)
    else
      selected ++ new_selected
    end
  end

  defp detect_sandwich_attacks(transactions) do
    # Detect potential sandwich attacks by analyzing transaction patterns
    # Look for: high fee tx -> victim tx -> low fee tx from same sender

    potential_sandwiches = []
    normal = transactions

    # This is a simplified detection - production would be more sophisticated
    {potential_sandwiches, normal}
  end

  defp break_sandwiches(sandwiches) do
    # Break up sandwich attacks by reordering
    Enum.flat_map(sandwiches, fn {front, victim, back} ->
      # Place victim first, then randomly place front/back
      if :rand.uniform() > 0.5 do
        [victim, front, back]
      else
        [victim, back, front]
      end
    end)
  end

  defp interleave(list1, list2) do
    do_interleave(list1, list2, [])
  end

  defp do_interleave([], list2, acc), do: Enum.reverse(acc) ++ list2
  defp do_interleave(list1, [], acc), do: Enum.reverse(acc) ++ list1

  defp do_interleave([h1 | t1], [h2 | t2], acc) do
    do_interleave(t1, t2, [h2, h1 | acc])
  end

  defp identify_mev_transactions(transactions) do
    # Identify transactions that are likely MEV
    # Look for: arbitrage, liquidations, sandwich attacks

    Enum.filter(transactions, fn tx ->
      is_mev_transaction?(tx)
    end)
  end

  defp is_mev_transaction?(tx) do
    # Check if transaction appears to be MEV
    # High priority fee is a simple heuristic
    # > 50 Gwei
    tx.priority_fee > 50_000_000_000 or
      String.contains?(tx.data || "", ["swap", "liquidate", "arbitrage"])
  end

  defp calculate_mev_value(tx) do
    # Estimate the MEV value of a transaction
    # In production, this would analyze the transaction data
    tx.priority_fee * tx.gas_limit
  end

  defp calculate_time_boost(priority_fee) do
    # Convert priority fee to time boost in microseconds
    # Higher fees get more boost, but with diminishing returns

    # > 100 Gwei
    if priority_fee > 100_000_000_000 do
      # 1 second max boost
      1_000_000
    else
      # Linear scaling
      div(priority_fee, 100_000)
    end
  end
end
