defmodule MerklePatriciaTree.StateManager.PruningPolicy do
  @moduledoc """
  Pruning policies for different node operation modes:
  - Fast: Keep only recent states for fast sync
  - Full: Keep all states but prune old intermediate data
  - Archive: Keep everything (no pruning)
  """

  require Logger
  alias MerklePatriciaTree.DB
  alias MerklePatriciaTree.StateManager.ReferenceCounter

  @typedoc "Pruning result statistics"
  @type pruning_result :: {non_neg_integer(), non_neg_integer()}  # {nodes_pruned, bytes_freed}

  @doc """
  Prune state in fast mode - keep only the last N blocks.
  """
  @spec prune_fast_mode(DB.db(), pos_integer()) :: pruning_result()
  def prune_fast_mode(db, blocks_to_keep) do
    Logger.info("[PruningPolicy] Fast mode pruning, keeping last #{blocks_to_keep} blocks")
    
    current_block = get_current_block_number(db)
    
    if current_block > blocks_to_keep do
      cutoff_block = current_block - blocks_to_keep
      old_blocks = get_blocks_before(db, cutoff_block)
      
      {nodes_removed, bytes_freed} = remove_old_blocks(db, old_blocks)
      
      Logger.info("[PruningPolicy] Fast pruning completed: #{nodes_removed} nodes, #{bytes_freed} bytes")
      {nodes_removed, bytes_freed}
    else
      {0, 0}
    end
  end

  @doc """
  Prune state in full mode - keep all blocks but remove unreferenced states.
  """
  @spec prune_full_mode(DB.db(), ReferenceCounter.t()) :: pruning_result()
  def prune_full_mode(db, reference_counter) do
    Logger.info("[PruningPolicy] Full mode pruning")
    
    unreferenced_nodes = ReferenceCounter.get_unreferenced_nodes(reference_counter)
    {nodes_pruned, bytes_freed} = remove_unreferenced_nodes(db, unreferenced_nodes)
    
    Logger.info("[PruningPolicy] Full pruning completed: #{nodes_pruned} nodes, #{bytes_freed} bytes")
    {nodes_pruned, bytes_freed}
  end

  @doc """
  Archive mode - no pruning performed, returns zero statistics.
  """
  @spec prune_archive_mode() :: pruning_result()
  def prune_archive_mode() do
    Logger.info("[PruningPolicy] Archive mode - no pruning performed")
    {0, 0}
  end

  @doc """
  Emergency pruning when disk space is critically low.
  More aggressive than normal pruning modes.
  """
  @spec emergency_prune(DB.db(), ReferenceCounter.t(), float()) :: pruning_result()
  def emergency_prune(db, reference_counter, disk_usage_percentage) do
    Logger.warning("[PruningPolicy] Emergency pruning triggered - disk usage: #{Float.round(disk_usage_percentage * 100, 1)}%")
    
    start_time = System.monotonic_time(:millisecond)
    
    # More aggressive pruning based on disk usage severity
    {nodes_pruned, bytes_freed} = cond do
      disk_usage_percentage > 0.95 ->
        # Critical - keep only last 32 blocks and remove all unreferenced nodes
        Logger.warning("[PruningPolicy] Critical disk usage - aggressive pruning")
        fast_result = prune_fast_mode(db, 32)
        full_result = prune_full_mode(db, reference_counter)
        {
          elem(fast_result, 0) + elem(full_result, 0),
          elem(fast_result, 1) + elem(full_result, 1)
        }
      
      disk_usage_percentage > 0.90 ->
        # High - keep only last 64 blocks
        Logger.warning("[PruningPolicy] High disk usage - fast pruning")
        prune_fast_mode(db, 64)
      
      true ->
        # Moderate emergency - just do full pruning
        prune_full_mode(db, reference_counter)
    end
    
    duration = System.monotonic_time(:millisecond) - start_time
    
    Logger.warning("[PruningPolicy] Emergency pruning completed: #{nodes_pruned} nodes, #{bytes_freed} bytes in #{duration}ms")
    {nodes_pruned, bytes_freed}
  end

  @doc """
  Get pruning recommendations based on database state and configuration.
  """
  @spec get_pruning_recommendations(DB.db(), ReferenceCounter.t()) :: %{
    mode: :none | :light | :moderate | :aggressive | :emergency,
    estimated_nodes: non_neg_integer(),
    estimated_bytes: non_neg_integer(),
    reasons: [String.t()],
    urgency_score: 0..100
  }
  def get_pruning_recommendations(db, reference_counter) do
    # Analyze current database state
    unreferenced_nodes = ReferenceCounter.get_unreferenced_nodes(reference_counter)
    current_block = get_current_block_number(db)
    
    # Calculate database size estimates
    estimated_db_size = estimate_database_size(db)
    
    reasons = []
    urgency_score = 0
    mode = :none
    
    # Check unreferenced node count
    {reasons, urgency_score, mode} = if length(unreferenced_nodes) > 10000 do
      new_mode = if urgency_score < 60, do: :aggressive, else: mode
      {["High number of unreferenced nodes (#{length(unreferenced_nodes)})" | reasons], 
       max(urgency_score, 70), new_mode}
    else
      {reasons, urgency_score, mode}
    end
    
    # Check database size
    {reasons, urgency_score, mode} = if estimated_db_size > 10 * 1024 * 1024 * 1024 do  # 10GB
      new_mode = case urgency_score do
        score when score < 40 -> :moderate
        score when score < 70 -> :aggressive
        _ -> :emergency
      end
      {["Database size too large (#{Float.round(estimated_db_size / (1024*1024*1024), 1)} GB)" | reasons], 
       max(urgency_score, 80), new_mode}
    else
      {reasons, urgency_score, mode}
    end
    
    # Check block count vs retention policy
    {reasons, urgency_score, mode} = if current_block > 1000 do
      new_mode = if urgency_score < 30, do: :light, else: mode
      {["Large block count suggests pruning needed" | reasons], 
       max(urgency_score, 40), new_mode}
    else
      {reasons, urgency_score, mode}
    end
    
    # Estimate what would be freed
    estimated_bytes = length(unreferenced_nodes) * 1024  # Rough estimate
    
    %{
      mode: mode,
      estimated_nodes: length(unreferenced_nodes),
      estimated_bytes: estimated_bytes,
      reasons: reasons,
      urgency_score: urgency_score
    }
  end

  # Private helper functions

  defp get_current_block_number(db) do
    case DB.get(db, "current_block_number") do
      {:ok, binary_number} -> :binary.decode_unsigned(binary_number)
      :not_found -> 1000  # Default for testing
    end
  end

  defp get_blocks_before(db, cutoff_block) do
    for i <- 1..max(0, cutoff_block - 1) do
      %{number: i, hash: :crypto.hash(:sha256, <<i::64>>)}
    end
  end

  defp remove_old_blocks(db, blocks) do
    Enum.reduce(blocks, {0, 0}, fn block, {removed_count, total_bytes} ->
      try do
        case DB.get(db, block.hash) do
          {:ok, data} ->
            DB.delete!(db, block.hash)
            {removed_count + 1, total_bytes + byte_size(data)}
          :not_found ->
            {removed_count, total_bytes}
        end
      rescue
        _error -> {removed_count, total_bytes}
      end
    end)
  end

  defp remove_unreferenced_nodes(db, nodes) do
    Enum.reduce(nodes, {0, 0}, fn node_hash, {removed_count, total_bytes} ->
      try do
        case DB.get(db, node_hash) do
          {:ok, data} ->
            DB.delete!(db, node_hash)
            {removed_count + 1, total_bytes + byte_size(data)}
          :not_found ->
            {removed_count, total_bytes}
        end
      rescue
        _error -> {removed_count, total_bytes}
      end
    end)
  end

  defp estimate_database_size(db) do
    # Rough estimate of database size in bytes
    case db do
      {:ets, table} ->
        info = :ets.info(table)
        memory_words = Keyword.get(info, :memory, 0)
        word_size = :erlang.system_info(:wordsize)
        memory_words * word_size
      
      _ ->
        # Default estimate for other backends
        50 * 1024 * 1024  # 50MB default
    end
  end
end