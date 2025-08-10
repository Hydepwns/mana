defmodule ExWire.Eth2.ForkChoiceBenchmark do
  @moduledoc """
  Benchmarks comparing optimized vs non-optimized fork choice implementations.
  
  Run with: mix run apps/ex_wire/lib/ex_wire/eth2/fork_choice_benchmark.ex
  """
  
  alias ExWire.Eth2.ForkChoice
  alias ExWire.Eth2.ForkChoiceOptimized
  
  def run do
    IO.puts("\n=== Fork Choice Performance Benchmark ===\n")
    
    # Test different tree sizes
    sizes = [10, 50, 100, 500, 1000]
    
    Enum.each(sizes, fn size ->
      IO.puts("\nTree size: #{size} blocks")
      IO.puts("=" |> String.duplicate(40))
      
      benchmark_implementation(size)
    end)
    
    IO.puts("\n=== Detailed Cache Performance ===\n")
    detailed_cache_benchmark()
    
    IO.puts("\n=== Memory Usage Comparison ===\n")
    memory_benchmark()
  end
  
  defp benchmark_implementation(tree_size) do
    # Create test data
    {blocks, attestations} = generate_test_data(tree_size)
    
    # Benchmark original implementation
    original_store = setup_original_store(blocks)
    original_times = benchmark_operations(original_store, attestations, "Original")
    
    # Benchmark optimized implementation
    optimized_store = setup_optimized_store(blocks)
    optimized_times = benchmark_operations(optimized_store, attestations, "Optimized")
    
    # Calculate improvements
    show_improvements(original_times, optimized_times)
  end
  
  defp benchmark_operations(store, attestations, label) do
    IO.puts("\n#{label} Implementation:")
    
    # Benchmark get_head
    {head_time, _} = :timer.tc(fn ->
      for _ <- 1..1000 do
        get_head(store)
      end
    end)
    head_avg = head_time / 1000
    IO.puts("  get_head: #{format_time(head_avg)}")
    
    # Benchmark attestation processing
    {attest_time, _} = :timer.tc(fn ->
      Enum.reduce(Enum.take(attestations, 100), store, fn att, acc ->
        process_attestation(acc, att)
      end)
    end)
    attest_avg = attest_time / 100
    IO.puts("  process_attestation: #{format_time(attest_avg)}")
    
    # Benchmark weight calculation
    {weight_time, _} = :timer.tc(fn ->
      for _ <- 1..1000 do
        calculate_weight(store, random_block_root())
      end
    end)
    weight_avg = weight_time / 1000
    IO.puts("  get_weight: #{format_time(weight_avg)}")
    
    %{
      get_head: head_avg,
      attestation: attest_avg,
      weight: weight_avg
    }
  end
  
  defp show_improvements(original, optimized) do
    IO.puts("\nPerformance Improvements:")
    
    head_improvement = (original.get_head / optimized.get_head - 1) * 100
    IO.puts("  get_head: #{format_improvement(head_improvement)}")
    
    attest_improvement = (original.attestation / optimized.attestation - 1) * 100
    IO.puts("  attestation: #{format_improvement(attest_improvement)}")
    
    weight_improvement = (original.weight / optimized.weight - 1) * 100
    IO.puts("  weight: #{format_improvement(weight_improvement)}")
    
    avg_improvement = (head_improvement + attest_improvement + weight_improvement) / 3
    IO.puts("  AVERAGE: #{format_improvement(avg_improvement)}")
  end
  
  defp detailed_cache_benchmark do
    sizes = [100, 500, 1000]
    
    Enum.each(sizes, fn size ->
      IO.puts("\nCache Performance (#{size} blocks):")
      
      # Setup optimized store
      {blocks, _} = generate_test_data(size)
      store = setup_optimized_store(blocks)
      
      # Get cache statistics
      stats = ForkChoiceOptimized.get_cache_stats(store)
      
      IO.puts("  Total blocks: #{stats.total_blocks}")
      IO.puts("  Cached weights: #{stats.cached_weights}")
      IO.puts("  Cache hit rate: #{stats.cache_hit_rate}%")
      
      # Measure cache effectiveness
      measure_cache_effectiveness(store)
    end)
  end
  
  defp measure_cache_effectiveness(store) do
    # Measure with cache
    {with_cache_time, _} = :timer.tc(fn ->
      for _ <- 1..10000 do
        ForkChoiceOptimized.get_head(store)
      end
    end)
    
    # Clear cache and measure
    store_no_cache = %{store | 
      best_child_cache: %{},
      best_descendant_cache: %{}
    }
    
    {without_cache_time, _} = :timer.tc(fn ->
      for _ <- 1..10000 do
        ForkChoiceOptimized.get_head(store_no_cache)
      end
    end)
    
    speedup = without_cache_time / with_cache_time
    IO.puts("  Cache speedup: #{Float.round(speedup, 2)}x")
    
    cache_benefit = (1 - with_cache_time / without_cache_time) * 100
    IO.puts("  Cache benefit: #{Float.round(cache_benefit, 1)}% reduction")
  end
  
  defp memory_benchmark do
    sizes = [100, 500, 1000]
    
    Enum.each(sizes, fn size ->
      {blocks, attestations} = generate_test_data(size)
      
      # Measure original
      original_store = setup_original_store(blocks)
      original_size = estimate_memory_size(original_store)
      
      # Measure optimized
      optimized_store = setup_optimized_store(blocks)
      optimized_size = estimate_memory_size(optimized_store)
      
      # Add attestations to see memory growth
      original_with_att = Enum.reduce(Enum.take(attestations, 100), original_store, fn att, acc ->
        process_attestation(acc, att)
      end)
      original_att_size = estimate_memory_size(original_with_att)
      
      optimized_with_att = Enum.reduce(Enum.take(attestations, 100), optimized_store, fn att, acc ->
        ForkChoiceOptimized.on_attestation(acc, att)
      end)
      optimized_att_size = estimate_memory_size(optimized_with_att)
      
      IO.puts("\nMemory Usage (#{size} blocks):")
      IO.puts("  Original:")
      IO.puts("    Base: #{format_bytes(original_size)}")
      IO.puts("    With attestations: #{format_bytes(original_att_size)}")
      IO.puts("    Growth: #{format_bytes(original_att_size - original_size)}")
      
      IO.puts("  Optimized:")
      IO.puts("    Base: #{format_bytes(optimized_size)}")
      IO.puts("    With attestations: #{format_bytes(optimized_att_size)}")
      IO.puts("    Growth: #{format_bytes(optimized_att_size - optimized_size)}")
      
      overhead = (optimized_size / original_size - 1) * 100
      IO.puts("  Cache overhead: #{Float.round(overhead, 1)}%")
    end)
  end
  
  # Helper Functions
  
  defp generate_test_data(block_count) do
    # Generate blocks
    blocks = for i <- 1..block_count do
      parent = if i == 1, do: <<0::256>>, else: <<(i-1)::256>>
      
      %{
        slot: i,
        parent_root: parent,
        root: <<i::256>>,
        state: create_mock_state(i)
      }
    end
    
    # Generate attestations
    attestations = for i <- 1..block_count * 2 do
      %{
        data: %{
          slot: rem(i, block_count) + 1,
          index: 0,
          beacon_block_root: <<rem(i, block_count) + 1::256>>,
          source: %{epoch: 0, root: <<0::256>>},
          target: %{epoch: div(i, 32), root: <<i::256>>}
        },
        aggregation_bits: <<0xFF>>,
        signature: <<0::768>>
      }
    end
    
    {blocks, attestations}
  end
  
  defp create_mock_state(slot) do
    %{
      slot: slot,
      validators: create_validators(100),
      balances: List.duplicate(32_000_000_000, 100),
      current_justified_checkpoint: %{epoch: 0, root: <<0::256>>},
      finalized_checkpoint: %{epoch: 0, root: <<0::256>>}
    }
  end
  
  defp create_validators(count) do
    for i <- 0..(count - 1) do
      %{
        pubkey: <<i::384>>,
        effective_balance: 32_000_000_000,
        activation_epoch: 0,
        exit_epoch: 0xFFFFFFFFFFFFFFFF
      }
    end
  end
  
  defp setup_original_store(blocks) do
    # Simplified original store structure
    genesis_state = create_mock_state(0)
    
    store = ForkChoice.init(
      genesis_state,
      <<0::256>>,
      System.system_time(:second)
    )
    
    # Add all blocks
    Enum.reduce(blocks, store, fn block_data, acc ->
      block = %{
        slot: block_data.slot,
        parent_root: block_data.parent_root
      }
      
      case ForkChoice.on_block(acc, block, block_data.root, block_data.state) do
        {:ok, new_store} -> new_store
        _ -> acc
      end
    end)
  end
  
  defp setup_optimized_store(blocks) do
    genesis_state = create_mock_state(0)
    
    store = ForkChoiceOptimized.init(
      genesis_state,
      <<0::256>>,
      System.system_time(:second)
    )
    
    # Add all blocks
    Enum.reduce(blocks, store, fn block_data, acc ->
      block = %{
        slot: block_data.slot,
        parent_root: block_data.parent_root
      }
      
      case ForkChoiceOptimized.on_block(acc, block, block_data.root, block_data.state) do
        {:ok, new_store} -> new_store
        _ -> acc
      end
    end)
  end
  
  defp get_head(store) do
    # Dispatch based on store type
    case store do
      %ForkChoice{} -> ForkChoice.get_head(store)
      %ForkChoiceOptimized{} -> ForkChoiceOptimized.get_head(store)
    end
  end
  
  defp process_attestation(store, attestation) do
    case store do
      %ForkChoice{} -> ForkChoice.on_attestation(store, attestation)
      %ForkChoiceOptimized{} -> ForkChoiceOptimized.on_attestation(store, attestation)
    end
  end
  
  defp calculate_weight(store, block_root) do
    case store do
      %ForkChoice{} -> get_weight_original(store, block_root)
      %ForkChoiceOptimized{} -> ForkChoiceOptimized.get_weight(store, block_root)
    end
  end
  
  defp get_weight_original(store, block_root) do
    # Simulate original O(n) weight calculation
    Map.get(store.blocks, block_root, %{})
    |> Map.get(:weight, 0)
  end
  
  defp random_block_root do
    <<:rand.uniform(1000)::256>>
  end
  
  defp estimate_memory_size(term) do
    :erlang.external_size(term)
  end
  
  defp format_time(microseconds) when microseconds < 1000 do
    "#{Float.round(microseconds, 2)}μs"
  end
  defp format_time(microseconds) when microseconds < 1_000_000 do
    "#{Float.round(microseconds / 1000, 2)}ms"
  end
  defp format_time(microseconds) do
    "#{Float.round(microseconds / 1_000_000, 2)}s"
  end
  
  defp format_improvement(percent) when percent > 0 do
    "+#{Float.round(percent, 1)}% faster"
  end
  defp format_improvement(percent) do
    "#{Float.round(abs(percent), 1)}% slower"
  end
  
  defp format_bytes(bytes) when bytes < 1024 do
    "#{bytes} B"
  end
  defp format_bytes(bytes) when bytes < 1024 * 1024 do
    "#{Float.round(bytes / 1024, 2)} KB"
  end
  defp format_bytes(bytes) do
    "#{Float.round(bytes / 1024 / 1024, 2)} MB"
  end
end

# Run the benchmark if executed directly
if Mix.env() != :test do
  # This can be manually called with ExWire.Eth2.ForkChoiceBenchmark.run()
end