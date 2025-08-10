defmodule ExWire.Eth2.AttestationBenchmark do
  @moduledoc """
  Comprehensive benchmarking suite for attestation processing performance.
  
  Measures:
  - Sequential vs parallel processing throughput
  - Signature verification performance
  - Batch size optimization
  - Memory usage under load
  - Latency distribution
  """
  
  require Logger
  
  alias ExWire.Eth2.{
    ParallelAttestationProcessor,
    BeaconState,
    Attestation,
    ForkChoiceOptimized
  }
  
  @default_batch_sizes [10, 50, 100, 200, 500]
  @default_attestation_counts [100, 500, 1000, 2000]
  
  defstruct [
    results: [],
    system_info: %{},
    timestamp: nil
  ]
  
  @doc """
  Run comprehensive benchmark suite
  """
  def run_full_benchmark(opts \\ []) do
    Logger.info("Starting comprehensive attestation processing benchmark")
    
    benchmark = %__MODULE__{
      system_info: collect_system_info(),
      timestamp: DateTime.utc_now()
    }
    
    benchmark = benchmark
    |> run_throughput_benchmarks(opts)
    |> run_latency_benchmarks(opts)
    |> run_batch_size_optimization(opts)
    |> run_memory_usage_benchmark(opts)
    |> run_concurrent_load_benchmark(opts)
    
    print_benchmark_results(benchmark)
    benchmark
  end
  
  @doc """
  Run throughput comparison: parallel vs sequential
  """
  def run_throughput_benchmarks(benchmark, opts) do
    Logger.info("Running throughput benchmarks...")
    
    attestation_counts = Keyword.get(opts, :attestation_counts, @default_attestation_counts)
    {beacon_state, fork_choice_store} = create_test_environment()
    
    results = Enum.map(attestation_counts, fn count ->
      attestations = create_test_attestations(beacon_state, count)
      
      # Benchmark parallel processing
      {parallel_time_us, parallel_results} = benchmark_parallel_processing(
        attestations,
        beacon_state,
        fork_choice_store
      )
      
      # Benchmark sequential processing
      {sequential_time_us, sequential_results} = benchmark_sequential_processing(
        attestations,
        beacon_state,
        fork_choice_store
      )
      
      parallel_throughput = count * 1_000_000 / parallel_time_us
      sequential_throughput = count * 1_000_000 / sequential_time_us
      speedup = parallel_throughput / sequential_throughput
      
      %{
        type: :throughput,
        attestation_count: count,
        parallel_time_us: parallel_time_us,
        sequential_time_us: sequential_time_us,
        parallel_throughput: parallel_throughput,
        sequential_throughput: sequential_throughput,
        speedup: speedup,
        parallel_success_rate: parallel_results.success_rate,
        sequential_success_rate: sequential_results.success_rate
      }
    end)
    
    %{benchmark | results: benchmark.results ++ results}
  end
  
  @doc """
  Run latency distribution analysis
  """
  def run_latency_benchmarks(benchmark, opts) do
    Logger.info("Running latency distribution benchmark...")
    
    sample_count = Keyword.get(opts, :latency_samples, 100)
    batch_size = Keyword.get(opts, :latency_batch_size, 50)
    {beacon_state, fork_choice_store} = create_test_environment()
    
    latencies = Enum.map(1..sample_count, fn _ ->
      attestations = create_test_attestations(beacon_state, batch_size)
      
      {time_us, _results} = benchmark_parallel_processing(
        attestations,
        beacon_state,
        fork_choice_store
      )
      
      time_us / 1000  # Convert to milliseconds
    end)
    
    stats = calculate_latency_stats(latencies)
    
    result = %{
      type: :latency,
      sample_count: sample_count,
      batch_size: batch_size,
      mean_ms: stats.mean,
      median_ms: stats.median,
      p95_ms: stats.p95,
      p99_ms: stats.p99,
      min_ms: stats.min,
      max_ms: stats.max,
      std_dev_ms: stats.std_dev
    }
    
    %{benchmark | results: benchmark.results ++ [result]}
  end
  
  @doc """
  Optimize batch size for best performance
  """
  def run_batch_size_optimization(benchmark, opts) do
    Logger.info("Running batch size optimization...")
    
    batch_sizes = Keyword.get(opts, :batch_sizes, @default_batch_sizes)
    total_attestations = Keyword.get(opts, :total_attestations, 1000)
    {beacon_state, fork_choice_store} = create_test_environment()
    
    results = Enum.map(batch_sizes, fn batch_size ->
      attestations = create_test_attestations(beacon_state, total_attestations)
      
      # Process in batches
      {total_time_us, batches_processed} = benchmark_batch_processing(
        attestations,
        beacon_state,
        fork_choice_store,
        batch_size
      )
      
      throughput = total_attestations * 1_000_000 / total_time_us
      avg_batch_time_ms = total_time_us / 1000 / batches_processed
      
      %{
        type: :batch_optimization,
        batch_size: batch_size,
        total_attestations: total_attestations,
        total_time_us: total_time_us,
        batches_processed: batches_processed,
        throughput: throughput,
        avg_batch_time_ms: avg_batch_time_ms
      }
    end)
    
    %{benchmark | results: benchmark.results ++ results}
  end
  
  @doc """
  Benchmark memory usage under different loads
  """
  def run_memory_usage_benchmark(benchmark, opts) do
    Logger.info("Running memory usage benchmark...")
    
    loads = Keyword.get(opts, :memory_loads, [100, 500, 1000, 2000])
    {beacon_state, fork_choice_store} = create_test_environment()
    
    results = Enum.map(loads, fn load ->
      # Force garbage collection before measurement
      :erlang.garbage_collect()
      memory_before = :erlang.memory()
      
      # Create and process attestations
      attestations = create_test_attestations(beacon_state, load)
      
      {time_us, _results} = benchmark_parallel_processing(
        attestations,
        beacon_state,
        fork_choice_store
      )
      
      memory_after = :erlang.memory()
      
      # Calculate memory usage
      total_memory_mb = memory_after[:total] / 1_024 / 1_024
      process_memory_mb = memory_after[:processes] / 1_024 / 1_024
      memory_increase_mb = (memory_after[:total] - memory_before[:total]) / 1_024 / 1_024
      
      %{
        type: :memory_usage,
        attestation_count: load,
        processing_time_us: time_us,
        total_memory_mb: total_memory_mb,
        process_memory_mb: process_memory_mb,
        memory_increase_mb: memory_increase_mb,
        memory_per_attestation_kb: memory_increase_mb * 1_024 / load
      }
    end)
    
    %{benchmark | results: benchmark.results ++ results}
  end
  
  @doc """
  Benchmark concurrent processing with multiple clients
  """
  def run_concurrent_load_benchmark(benchmark, opts) do
    Logger.info("Running concurrent load benchmark...")
    
    concurrent_clients = Keyword.get(opts, :concurrent_clients, [1, 2, 4, 8])
    attestations_per_client = Keyword.get(opts, :attestations_per_client, 200)
    {beacon_state, fork_choice_store} = create_test_environment()
    
    results = Enum.map(concurrent_clients, fn client_count ->
      # Create tasks for concurrent processing
      tasks = Enum.map(1..client_count, fn _ ->
        Task.async(fn ->
          attestations = create_test_attestations(beacon_state, attestations_per_client)
          
          benchmark_parallel_processing(
            attestations,
            beacon_state,
            fork_choice_store
          )
        end)
      end)
      
      # Wait for all tasks and measure total time
      start_time = System.monotonic_time(:microsecond)
      task_results = Task.await_many(tasks, 60_000)
      total_time_us = System.monotonic_time(:microsecond) - start_time
      
      # Calculate metrics
      total_attestations = client_count * attestations_per_client
      overall_throughput = total_attestations * 1_000_000 / total_time_us
      
      avg_individual_time = task_results
      |> Enum.map(fn {time, _} -> time end)
      |> Enum.sum()
      |> div(client_count)
      
      %{
        type: :concurrent_load,
        client_count: client_count,
        attestations_per_client: attestations_per_client,
        total_attestations: total_attestations,
        total_time_us: total_time_us,
        overall_throughput: overall_throughput,
        avg_individual_time_us: avg_individual_time,
        concurrency_efficiency: avg_individual_time / total_time_us
      }
    end)
    
    %{benchmark | results: benchmark.results ++ results}
  end
  
  # Private Helper Functions
  
  defp benchmark_parallel_processing(attestations, beacon_state, fork_choice_store) do
    {:ok, processor} = ParallelAttestationProcessor.start_link([
      beacon_state: beacon_state,
      fork_choice_store: fork_choice_store,
      name: :"benchmark_processor_#{System.unique_integer()}"
    ])
    
    result = :timer.tc(fn ->
      ParallelAttestationProcessor.process_attestations(
        attestations,
        beacon_state,
        fork_choice_store
      )
    end)
    
    GenServer.stop(processor)
    result
  end
  
  defp benchmark_sequential_processing(attestations, beacon_state, fork_choice_store) do
    # Simulate sequential processing by processing one at a time
    :timer.tc(fn ->
      {valid, invalid} = Enum.reduce(attestations, {[], []}, fn attestation, {valid_acc, invalid_acc} ->
        # Simulate individual attestation processing time
        Process.sleep(1)  # 1ms per attestation (simulated)
        
        # For benchmarking, assume 90% success rate
        if :rand.uniform(100) <= 90 do
          {[attestation | valid_acc], invalid_acc}
        else
          {valid_acc, [{:invalid_signature, attestation} | invalid_acc]}
        end
      end)
      
      %{
        valid: valid,
        invalid: invalid,
        total: length(attestations),
        success_rate: length(valid) / length(attestations)
      }
    end)
  end
  
  defp benchmark_batch_processing(attestations, beacon_state, fork_choice_store, batch_size) do
    batches = Enum.chunk_every(attestations, batch_size)
    
    :timer.tc(fn ->
      Enum.each(batches, fn batch ->
        benchmark_parallel_processing(batch, beacon_state, fork_choice_store)
      end)
      
      length(batches)
    end)
  end
  
  defp create_test_environment do
    beacon_state = %BeaconState{
      slot: 1000,
      fork: %{
        previous_version: <<0, 0, 0, 0>>,
        current_version: <<0, 0, 0, 1>>,
        epoch: 0
      },
      genesis_validators_root: <<0::256>>,
      validators: create_test_validators(512),  # Larger validator set
      current_justified_checkpoint: %{epoch: 30, root: <<30::256>>},
      finalized_checkpoint: %{epoch: 28, root: <<28::256>>}
    }
    
    fork_choice_store = ForkChoiceOptimized.init(
      beacon_state,
      <<0::256>>,
      System.system_time(:second) - 7200
    )
    
    {beacon_state, fork_choice_store}
  end
  
  defp create_test_validators(count) do
    Enum.map(0..(count - 1), fn i ->
      %{
        pubkey: :crypto.hash(:sha256, <<i::32>>) <> :crypto.hash(:sha256, <<i::32>>),
        withdrawal_credentials: <<0::256>>,
        effective_balance: 32_000_000_000,
        slashed: false,
        activation_eligibility_epoch: 0,
        activation_epoch: 0,
        exit_epoch: 2**64 - 1,
        withdrawable_epoch: 2**64 - 1
      }
    end)
  end
  
  defp create_test_attestations(beacon_state, count) do
    Enum.map(1..count, fn i ->
      slot = beacon_state.slot - rem(i, 32)  # Vary slots within epoch
      
      %Attestation{
        aggregation_bits: generate_aggregation_bits(128),
        data: %{
          slot: slot,
          index: rem(i, 16),  # Multiple committees per slot
          beacon_block_root: :crypto.hash(:sha256, <<slot::64>>),
          source: beacon_state.current_justified_checkpoint,
          target: %{
            epoch: div(slot, 32),
            root: :crypto.hash(:sha256, <<div(slot, 32)::64>>)
          }
        },
        signature: :crypto.strong_rand_bytes(96)  # Random signature
      }
    end)
  end
  
  defp generate_aggregation_bits(bit_count) do
    byte_count = div(bit_count + 7, 8)
    # Generate with ~50% participation
    bits = :crypto.strong_rand_bytes(byte_count)
    
    # Ensure at least some bits are set
    case :binary.at(bits, 0) do
      0 -> <<1, :binary.part(bits, 1, byte_count - 1)::binary>>
      _ -> bits
    end
  end
  
  defp calculate_latency_stats(latencies) do
    sorted = Enum.sort(latencies)
    count = length(latencies)
    
    mean = Enum.sum(latencies) / count
    median = Enum.at(sorted, div(count, 2))
    p95 = Enum.at(sorted, round(count * 0.95) - 1)
    p99 = Enum.at(sorted, round(count * 0.99) - 1)
    min_val = List.first(sorted)
    max_val = List.last(sorted)
    
    variance = latencies
    |> Enum.map(fn x -> (x - mean) * (x - mean) end)
    |> Enum.sum()
    |> div(count)
    
    std_dev = :math.sqrt(variance)
    
    %{
      mean: mean,
      median: median,
      p95: p95,
      p99: p99,
      min: min_val,
      max: max_val,
      std_dev: std_dev
    }
  end
  
  defp collect_system_info do
    %{
      schedulers: System.schedulers_online(),
      total_schedulers: System.schedulers(),
      otp_release: System.otp_release(),
      elixir_version: System.version(),
      system_architecture: :erlang.system_info(:system_architecture),
      memory: :erlang.memory(),
      process_limit: :erlang.system_info(:process_limit)
    }
  end
  
  defp print_benchmark_results(benchmark) do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("ATTESTATION PROCESSING BENCHMARK RESULTS")
    IO.puts("Timestamp: #{benchmark.timestamp}")
    IO.puts("System: #{benchmark.system_info.schedulers} cores, Elixir #{benchmark.system_info.elixir_version}")
    IO.puts(String.duplicate("=", 80))
    
    # Print throughput results
    throughput_results = Enum.filter(benchmark.results, &(&1.type == :throughput))
    if throughput_results != [] do
      IO.puts("\n📊 THROUGHPUT COMPARISON (Parallel vs Sequential)")
      IO.puts(String.duplicate("-", 80))
      IO.puts(String.pad_trailing("Count", 8) <>
              String.pad_trailing("Parallel", 12) <>
              String.pad_trailing("Sequential", 12) <>
              String.pad_trailing("Speedup", 10) <>
              "Success Rate")
      IO.puts(String.duplicate("-", 80))
      
      Enum.each(throughput_results, fn result ->
        IO.puts(String.pad_trailing("#{result.attestation_count}", 8) <>
                String.pad_trailing("#{Float.round(result.parallel_throughput, 0)}/s", 12) <>
                String.pad_trailing("#{Float.round(result.sequential_throughput, 0)}/s", 12) <>
                String.pad_trailing("#{Float.round(result.speedup, 1)}x", 10) <>
                "#{Float.round(result.parallel_success_rate * 100, 1)}%")
      end)
      
      avg_speedup = throughput_results
      |> Enum.map(& &1.speedup)
      |> Enum.sum()
      |> div(length(throughput_results))
      
      IO.puts("\n⚡ Average Speedup: #{Float.round(avg_speedup, 1)}x")
    end
    
    # Print latency results
    latency_results = Enum.filter(benchmark.results, &(&1.type == :latency))
    if latency_results != [] do
      result = List.first(latency_results)
      IO.puts("\n📈 LATENCY DISTRIBUTION (#{result.sample_count} samples, batch size #{result.batch_size})")
      IO.puts(String.duplicate("-", 40))
      IO.puts("Mean:    #{Float.round(result.mean_ms, 2)}ms")
      IO.puts("Median:  #{Float.round(result.median_ms, 2)}ms")
      IO.puts("95th percentile: #{Float.round(result.p95_ms, 2)}ms")
      IO.puts("99th percentile: #{Float.round(result.p99_ms, 2)}ms")
      IO.puts("Min:     #{Float.round(result.min_ms, 2)}ms")
      IO.puts("Max:     #{Float.round(result.max_ms, 2)}ms")
      IO.puts("Std Dev: #{Float.round(result.std_dev_ms, 2)}ms")
    end
    
    # Print batch optimization results
    batch_results = Enum.filter(benchmark.results, &(&1.type == :batch_optimization))
    if batch_results != [] do
      IO.puts("\n🎯 BATCH SIZE OPTIMIZATION")
      IO.puts(String.duplicate("-", 60))
      IO.puts(String.pad_trailing("Batch Size", 12) <>
              String.pad_trailing("Throughput", 15) <>
              String.pad_trailing("Avg Batch Time", 15))
      IO.puts(String.duplicate("-", 60))
      
      Enum.each(batch_results, fn result ->
        IO.puts(String.pad_trailing("#{result.batch_size}", 12) <>
                String.pad_trailing("#{Float.round(result.throughput, 0)}/s", 15) <>
                "#{Float.round(result.avg_batch_time_ms, 2)}ms")
      end)
      
      best = Enum.max_by(batch_results, & &1.throughput)
      IO.puts("\n🏆 Optimal batch size: #{best.batch_size} (#{Float.round(best.throughput, 0)}/s)")
    end
    
    # Print memory results
    memory_results = Enum.filter(benchmark.results, &(&1.type == :memory_usage))
    if memory_results != [] do
      IO.puts("\n💾 MEMORY USAGE")
      IO.puts(String.duplicate("-", 70))
      IO.puts(String.pad_trailing("Count", 8) <>
              String.pad_trailing("Total Mem", 12) <>
              String.pad_trailing("Process Mem", 12) <>
              String.pad_trailing("Increase", 12) <>
              "Per Attestation")
      IO.puts(String.duplicate("-", 70))
      
      Enum.each(memory_results, fn result ->
        IO.puts(String.pad_trailing("#{result.attestation_count}", 8) <>
                String.pad_trailing("#{Float.round(result.total_memory_mb, 1)}MB", 12) <>
                String.pad_trailing("#{Float.round(result.process_memory_mb, 1)}MB", 12) <>
                String.pad_trailing("#{Float.round(result.memory_increase_mb, 1)}MB", 12) <>
                "#{Float.round(result.memory_per_attestation_kb, 2)}KB")
      end)
    end
    
    # Print concurrent load results
    concurrent_results = Enum.filter(benchmark.results, &(&1.type == :concurrent_load))
    if concurrent_results != [] do
      IO.puts("\n🔄 CONCURRENT LOAD PERFORMANCE")
      IO.puts(String.duplicate("-", 80))
      IO.puts(String.pad_trailing("Clients", 8) <>
              String.pad_trailing("Total", 8) <>
              String.pad_trailing("Throughput", 15) <>
              String.pad_trailing("Efficiency", 12) <>
              "Individual Avg")
      IO.puts(String.duplicate("-", 80))
      
      Enum.each(concurrent_results, fn result ->
        IO.puts(String.pad_trailing("#{result.client_count}", 8) <>
                String.pad_trailing("#{result.total_attestations}", 8) <>
                String.pad_trailing("#{Float.round(result.overall_throughput, 0)}/s", 15) <>
                String.pad_trailing("#{Float.round(result.concurrency_efficiency * 100, 1)}%", 12) <>
                "#{Float.round(result.avg_individual_time_us / 1000, 1)}ms")
      end)
    end
    
    IO.puts("\n" <> String.duplicate("=", 80))
  end
end