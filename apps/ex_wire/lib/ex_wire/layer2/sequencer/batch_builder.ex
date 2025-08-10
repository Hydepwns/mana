defmodule ExWire.Layer2.Sequencer.BatchBuilder do
  @moduledoc """
  Batch builder for creating transaction batches for rollups.
  """

  alias ExWire.Layer2.Batch

  @doc """
  Builds a batch from a list of transactions.
  """
  def build(transactions, sequence_number, rollup_id) do
    previous_root = get_previous_root(rollup_id)
    sequencer_address = get_sequencer_address()

    batch =
      Batch.new(
        sequence_number,
        transactions,
        previous_root,
        sequencer_address
      )

    # Compute state root (simplified for testing)
    state_root = compute_state_root(batch)

    %{batch | state_root: state_root}
  end

  defp get_previous_root(_rollup_id) do
    # In production, would fetch from rollup state
    :crypto.strong_rand_bytes(32)
  end

  defp get_sequencer_address() do
    # In production, would use actual sequencer address
    <<1::160>>
  end

  defp compute_state_root(batch) do
    # Simplified state root computation
    data = :erlang.term_to_binary(batch.transactions)
    :crypto.hash(:sha256, data)
  end
end
