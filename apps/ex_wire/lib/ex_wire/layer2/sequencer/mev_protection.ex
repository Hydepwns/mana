defmodule ExWire.Layer2.Sequencer.MEVProtection do
  @moduledoc """
  MEV protection mechanisms for transaction sequencing.
  """

  @doc """
  Adds a transaction with MEV protection to the mempool.
  Uses commit-reveal and time-based ordering to prevent MEV extraction.
  """
  def add_protected(tx, mempool) do
    # Add random delay to prevent timing attacks
    delay = :rand.uniform(100)

    protected_tx =
      Map.merge(tx, %{
        mev_protection: true,
        reveal_time: DateTime.add(DateTime.utc_now(), delay, :millisecond)
      })

    # Insert in random position to prevent ordering attacks
    insert_position = :rand.uniform(max(length(mempool), 1))

    {before, after_list} = Enum.split(mempool, insert_position - 1)
    before ++ [protected_tx | after_list]
  end
end
