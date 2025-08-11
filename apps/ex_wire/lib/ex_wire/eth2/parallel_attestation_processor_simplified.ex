defmodule ExWire.Eth2.ParallelAttestationProcessorSimplified do
  @moduledoc """
  Simplified parallel attestation processor for testing Flow performance.

  This version focuses on the parallel processing architecture without 
  requiring BLS signature verification to work around compilation issues.
  """

  use GenServer
  require Logger
  import Bitwise

  alias ExWire.Eth2.Attestation

  # Configuration
  @max_parallel_workers System.schedulers_online() * 2
  @batch_size 100
  @batch_timeout_ms 50
  @signature_verification_stages 4
  @max_pending_attestations 10_000

  defstruct [
    :beacon_state,
    :fork_choice_store,
    pending_attestations: [],
    processing_stats: %{
      total_processed: 0,
      total_validated: 0,
      total_rejected: 0,
      average_batch_time_ms: 0,
      current_throughput: 0
    },
    batch_processor: nil
  ]

  @type validation_result :: {:ok, Attestation.t()} | {:error, atom(), Attestation.t()}

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  def process_attestations(attestations, beacon_state, fork_choice_store) do
    GenServer.call(
      __MODULE__,
      {:process_batch, attestations, beacon_state, fork_choice_store},
      30_000
    )
  end

  def process_attestation(attestation, beacon_state, fork_choice_store) do
    GenServer.cast(__MODULE__, {:queue_attestation, attestation, beacon_state, fork_choice_store})
  end

  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    Logger.info(
      "Starting Simplified Parallel Attestation Processor with #{@max_parallel_workers} workers"
    )

    schedule_batch_processing()

    state = %__MODULE__{
      beacon_state: opts[:beacon_state],
      fork_choice_store: opts[:fork_choice_store]
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:process_batch, attestations, beacon_state, fork_choice_store}, _from, state) do
    start_time = System.monotonic_time(:millisecond)

    # Process attestations in parallel using Flow
    results = process_attestations_parallel(attestations, beacon_state, fork_choice_store)

    # Update statistics
    elapsed_ms = System.monotonic_time(:millisecond) - start_time
    state = update_processing_stats(state, results, elapsed_ms)

    Logger.info("Processed #{length(attestations)} attestations in #{elapsed_ms}ms")

    {:reply, results, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.processing_stats, state}
  end

  @impl true
  def handle_cast({:queue_attestation, attestation, beacon_state, fork_choice_store}, state) do
    # Add to pending queue
    pending = [{attestation, beacon_state, fork_choice_store} | state.pending_attestations]

    state = %{state | pending_attestations: pending}

    # Process immediately if batch is full
    state =
      if length(pending) >= @batch_size do
        process_pending_batch(state)
      else
        state
      end

    # Apply back-pressure if queue is too large
    if length(state.pending_attestations) > @max_pending_attestations do
      Logger.warning("Attestation queue overflow, applying back-pressure")
      Process.sleep(10)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:process_batch, state) do
    # Process any pending attestations
    state =
      if length(state.pending_attestations) > 0 do
        process_pending_batch(state)
      else
        state
      end

    # Schedule next batch
    schedule_batch_processing()

    {:noreply, state}
  end

  # Private Functions - Parallel Processing with Flow

  defp process_attestations_parallel(attestations, beacon_state, fork_choice_store) do
    attestations
    |> Flow.from_enumerable(max_demand: @batch_size, stages: @max_parallel_workers)
    |> Flow.partition(stages: @signature_verification_stages, hash: &attestation_hash/1)
    |> Flow.map(fn attestation ->
      # Stage 1: Basic validation
      with {:ok, attestation} <- validate_attestation_data(attestation, beacon_state),
           # Stage 2: Committee validation  
           {:ok, committee} <- get_attestation_committee(attestation, beacon_state),
           # Stage 3: Simplified signature check (skip BLS for now)
           {:ok, attestation} <-
             validate_attestation_signature_simplified(attestation, committee, beacon_state),
           # Stage 4: Fork choice validation
           {:ok, attestation} <- validate_for_fork_choice(attestation, fork_choice_store) do
        {:ok, attestation}
      else
        {:error, reason} -> {:error, reason, attestation}
      end
    end)
    |> Flow.partition(window: Flow.Window.count(@batch_size))
    |> Flow.reduce(fn -> {[], []} end, fn
      {:ok, attestation}, {valid, invalid} ->
        {[attestation | valid], invalid}

      {:error, reason, attestation}, {valid, invalid} ->
        {valid, [{reason, attestation} | invalid]}
    end)
    |> Flow.emit(:state)
    |> Enum.to_list()
    |> process_flow_results()
  end

  defp process_flow_results(results) do
    {valid, invalid} = List.first(results, {[], []})

    %{
      valid: Enum.reverse(valid),
      invalid: Enum.reverse(invalid),
      total: length(valid) + length(invalid),
      success_rate:
        if(length(valid) + length(invalid) > 0,
          do: length(valid) / (length(valid) + length(invalid)),
          else: 0
        )
    }
  end

  # Validation Functions (executed in parallel)

  defp validate_attestation_data(attestation, beacon_state) do
    data = attestation.data
    current_slot = beacon_state.slot

    cond do
      # Check slot bounds
      data.slot > current_slot ->
        {:error, :future_slot}

      data.slot + 32 < current_slot ->
        {:error, :old_slot}

      # Check target epoch
      compute_epoch_at_slot(data.slot) != data.target.epoch ->
        {:error, :invalid_target_epoch}

      # Check if block exists (simplified)
      not block_exists?(data.beacon_block_root) ->
        {:error, :unknown_block}

      true ->
        {:ok, attestation}
    end
  end

  defp get_attestation_committee(attestation, beacon_state) do
    try do
      committee =
        compute_committee(
          beacon_state,
          attestation.data.slot,
          attestation.data.index
        )

      if length(committee) > 0 do
        {:ok, committee}
      else
        {:error, :invalid_committee}
      end
    rescue
      _ -> {:error, :committee_computation_failed}
    end
  end

  # Simplified signature validation without BLS
  defp validate_attestation_signature_simplified(attestation, committee, beacon_state) do
    # Get participating validators
    participating_indices = get_participating_indices(attestation.aggregation_bits, committee)

    if length(participating_indices) == 0 do
      {:error, :no_participants}
    else
      # For testing: simulate signature verification with 95% success rate
      # In production, this would do actual BLS signature verification
      if :rand.uniform(100) <= 95 do
        {:ok, attestation}
      else
        {:error, :invalid_signature}
      end
    end
  end

  defp validate_for_fork_choice(attestation, fork_choice_store) do
    # Check if attestation is for a known block in fork choice
    if has_block?(fork_choice_store, attestation.data.beacon_block_root) do
      {:ok, attestation}
    else
      {:error, :not_in_fork_choice}
    end
  end

  # Helper Functions

  defp process_pending_batch(state) do
    if state.pending_attestations == [] do
      state
    else
      # Extract attestations and their contexts
      {attestations, contexts} = Enum.unzip(state.pending_attestations)
      {beacon_state, fork_choice_store} = List.first(contexts)

      # Process in parallel
      results = process_attestations_parallel(attestations, beacon_state, fork_choice_store)

      # Update state
      %{
        state
        | pending_attestations: [],
          processing_stats: update_stats_from_results(state.processing_stats, results)
      }
    end
  end

  defp update_processing_stats(state, results, elapsed_ms) do
    stats = state.processing_stats

    total_processed = stats.total_processed + results.total
    total_validated = stats.total_validated + length(results.valid)
    total_rejected = stats.total_rejected + length(results.invalid)

    # Update moving average of batch time
    avg_batch_time =
      if stats.total_processed == 0 do
        elapsed_ms
      else
        stats.average_batch_time_ms * 0.9 + elapsed_ms * 0.1
      end

    # Calculate throughput
    throughput =
      if elapsed_ms > 0 do
        results.total * 1000 / elapsed_ms
      else
        0
      end

    %{
      state
      | processing_stats: %{
          total_processed: total_processed,
          total_validated: total_validated,
          total_rejected: total_rejected,
          average_batch_time_ms: avg_batch_time,
          current_throughput: throughput
        }
    }
  end

  defp update_stats_from_results(stats, results) do
    %{
      stats
      | total_processed: stats.total_processed + results.total,
        total_validated: stats.total_validated + length(results.valid),
        total_rejected: stats.total_rejected + length(results.invalid)
    }
  end

  defp attestation_hash(attestation) do
    # Hash for partitioning work across Flow stages
    :erlang.phash2({
      attestation.data.slot,
      attestation.data.index,
      attestation.data.beacon_block_root
    })
  end

  defp get_participating_indices(aggregation_bits, committee) do
    aggregation_bits
    |> :binary.bin_to_list()
    |> Enum.with_index()
    |> Enum.filter(fn {byte, byte_idx} ->
      Enum.any?(0..7, fn bit_idx ->
        idx = byte_idx * 8 + bit_idx
        idx < length(committee) && bit_set?(byte, bit_idx)
      end)
    end)
    |> Enum.flat_map(fn {byte, byte_idx} ->
      Enum.filter(0..7, fn bit_idx ->
        idx = byte_idx * 8 + bit_idx
        idx < length(committee) && bit_set?(byte, bit_idx)
      end)
      |> Enum.map(fn bit_idx ->
        idx = byte_idx * 8 + bit_idx
        Enum.at(committee, idx)
      end)
    end)
  end

  defp bit_set?(byte, bit_index) do
    (byte &&& 1 <<< bit_index) != 0
  end

  defp block_exists?(block_root) do
    # Simplified - assume most blocks exist for testing
    # 95% success rate
    rem(:erlang.phash2(block_root), 100) > 5
  end

  defp has_block?(fork_choice_store, block_root) do
    Map.has_key?(fork_choice_store.blocks || %{}, block_root)
  end

  defp compute_committee(beacon_state, slot, index) do
    # Simplified committee computation for testing
    epoch = compute_epoch_at_slot(slot)
    active_validators = get_active_validator_indices(beacon_state, epoch)

    # Simple committee selection
    committee_size = min(128, div(length(active_validators), 32))
    start_idx = index * committee_size

    Enum.slice(active_validators, start_idx, committee_size)
  end

  defp get_active_validator_indices(beacon_state, epoch) do
    beacon_state.validators
    |> Enum.with_index()
    |> Enum.filter(fn {validator, _} ->
      validator.activation_epoch <= epoch && epoch < validator.exit_epoch
    end)
    |> Enum.map(fn {_, index} -> index end)
  end

  defp compute_epoch_at_slot(slot) do
    div(slot, 32)
  end

  defp schedule_batch_processing do
    Process.send_after(self(), :process_batch, @batch_timeout_ms)
  end
end
