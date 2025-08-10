defmodule ExWire.Layer2.Optimistic.OptimisticRollup do
  @moduledoc """
  Optimistic rollup implementation supporting Optimism and Arbitrum protocols.

  Features:
  - Fraud proof generation and verification
  - Challenge period management
  - Dispute resolution system
  - Withdrawal processing with time delays
  """

  use GenServer
  require Logger

  alias ExWire.Layer2.{Rollup, Batch}
  alias ExWire.Layer2.Optimistic.{FraudProof, ChallengeManager, WithdrawalManager}

  @type challenge_status :: :none | :pending | :proven | :expired

  @type t :: %__MODULE__{
          rollup_id: String.t(),
          challenge_period: non_neg_integer(),
          challenges: map(),
          withdrawals: map(),
          fraud_proofs: list(),
          dispute_game_factory: binary() | nil
        }

  defstruct [
    :rollup_id,
    :challenge_period,
    :dispute_game_factory,
    challenges: %{},
    withdrawals: %{},
    fraud_proofs: []
  ]

  # Client API

  @doc """
  Starts an optimistic rollup manager.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: via_tuple(opts[:rollup_id]))
  end

  @doc """
  Initiates a challenge against a state root.
  """
  @spec challenge_state(String.t(), non_neg_integer(), binary()) ::
          {:ok, String.t()} | {:error, term()}
  def challenge_state(rollup_id, batch_number, claimed_state_root) do
    GenServer.call(via_tuple(rollup_id), {:challenge_state, batch_number, claimed_state_root})
  end

  @doc """
  Submits a fraud proof for a challenged state.
  """
  @spec submit_fraud_proof(String.t(), String.t(), binary()) ::
          {:ok, :accepted | :rejected} | {:error, term()}
  def submit_fraud_proof(rollup_id, challenge_id, proof) do
    GenServer.call(via_tuple(rollup_id), {:submit_fraud_proof, challenge_id, proof})
  end

  @doc """
  Initiates a withdrawal from L2 to L1.
  """
  @spec initiate_withdrawal(String.t(), map()) ::
          {:ok, String.t()} | {:error, term()}
  def initiate_withdrawal(rollup_id, withdrawal_params) do
    GenServer.call(via_tuple(rollup_id), {:initiate_withdrawal, withdrawal_params})
  end

  @doc """
  Finalizes a withdrawal after the challenge period.
  """
  @spec finalize_withdrawal(String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def finalize_withdrawal(rollup_id, withdrawal_id) do
    GenServer.call(via_tuple(rollup_id), {:finalize_withdrawal, withdrawal_id})
  end

  @doc """
  Resolves a dispute game for Optimism's fault dispute system.
  """
  @spec resolve_dispute(String.t(), String.t()) ::
          {:ok, :defender_wins | :challenger_wins} | {:error, term()}
  def resolve_dispute(rollup_id, dispute_id) do
    GenServer.call(via_tuple(rollup_id), {:resolve_dispute, dispute_id})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    Logger.info("Starting Optimistic Rollup: #{opts[:rollup_id]}")

    state = %__MODULE__{
      rollup_id: opts[:rollup_id],
      # 7 days
      challenge_period: opts[:challenge_period] || 7 * 24 * 60 * 60,
      dispute_game_factory: opts[:dispute_game_factory]
    }

    # Start the base rollup process
    {:ok, _pid} =
      Rollup.start_link(
        id: opts[:rollup_id],
        type: :optimistic,
        config: %{
          challenge_period: state.challenge_period,
          fraud_proof_window: 24 * 60 * 60
        }
      )

    # Schedule periodic challenge expiry checks
    # Every minute
    Process.send_after(self(), :check_challenge_expiry, 60_000)

    {:ok, state}
  end

  @impl true
  def handle_call({:challenge_state, batch_number, claimed_state_root}, _from, state) do
    challenge_id = generate_challenge_id()

    challenge = %{
      id: challenge_id,
      batch_number: batch_number,
      claimed_state_root: claimed_state_root,
      challenger: get_caller_address(),
      created_at: DateTime.utc_now(),
      expires_at: DateTime.add(DateTime.utc_now(), state.challenge_period, :second),
      status: :pending,
      bond: calculate_challenge_bond()
    }

    new_challenges = Map.put(state.challenges, challenge_id, challenge)

    Logger.info("Challenge initiated: #{challenge_id} for batch #{batch_number}")

    # Emit challenge event
    emit_challenge_event(challenge)

    {:reply, {:ok, challenge_id}, %{state | challenges: new_challenges}}
  end

  @impl true
  def handle_call({:submit_fraud_proof, challenge_id, proof}, _from, state) do
    case Map.get(state.challenges, challenge_id) do
      nil ->
        {:reply, {:error, :challenge_not_found}, state}

      challenge when challenge.status != :pending ->
        {:reply, {:error, :challenge_not_pending}, state}

      challenge ->
        case verify_fraud_proof(challenge, proof) do
          {:ok, true} ->
            # Fraud proof is valid - challenger wins
            updated_challenge = %{
              challenge
              | status: :proven,
                proof: proof,
                resolved_at: DateTime.utc_now()
            }

            new_challenges = Map.put(state.challenges, challenge_id, updated_challenge)
            new_fraud_proofs = [proof | state.fraud_proofs]

            # Trigger state rollback
            rollback_state(state.rollup_id, challenge.batch_number)

            # Slash the sequencer/proposer
            slash_proposer(challenge)

            Logger.warn("Fraud proof accepted for challenge #{challenge_id}")

            {:reply, {:ok, :accepted},
             %{state | challenges: new_challenges, fraud_proofs: new_fraud_proofs}}

          {:ok, false} ->
            # Fraud proof is invalid - defender wins
            Logger.info("Fraud proof rejected for challenge #{challenge_id}")
            {:reply, {:ok, :rejected}, state}

          {:error, reason} = error ->
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:initiate_withdrawal, params}, _from, state) do
    withdrawal_id = generate_withdrawal_id()

    withdrawal = %{
      id: withdrawal_id,
      from: params[:from],
      to: params[:to],
      token: params[:token] || :eth,
      amount: params[:amount],
      data: params[:data],
      initiated_at: DateTime.utc_now(),
      finalized_at: nil,
      ready_at: DateTime.add(DateTime.utc_now(), state.challenge_period, :second),
      status: :pending,
      proof: params[:proof]
    }

    new_withdrawals = Map.put(state.withdrawals, withdrawal_id, withdrawal)

    Logger.info("Withdrawal initiated: #{withdrawal_id}")

    {:reply, {:ok, withdrawal_id}, %{state | withdrawals: new_withdrawals}}
  end

  @impl true
  def handle_call({:finalize_withdrawal, withdrawal_id}, _from, state) do
    case Map.get(state.withdrawals, withdrawal_id) do
      nil ->
        {:reply, {:error, :withdrawal_not_found}, state}

      withdrawal when withdrawal.status != :pending ->
        {:reply, {:error, :withdrawal_not_pending}, state}

      withdrawal ->
        if DateTime.compare(DateTime.utc_now(), withdrawal.ready_at) == :lt do
          {:reply, {:error, :challenge_period_not_expired}, state}
        else
          # Process the withdrawal on L1
          case process_l1_withdrawal(withdrawal) do
            :ok ->
              updated_withdrawal = %{
                withdrawal
                | status: :finalized,
                  finalized_at: DateTime.utc_now()
              }

              new_withdrawals = Map.put(state.withdrawals, withdrawal_id, updated_withdrawal)

              Logger.info("Withdrawal finalized: #{withdrawal_id}")

              {:reply, {:ok, updated_withdrawal}, %{state | withdrawals: new_withdrawals}}

            {:error, reason} = error ->
              {:reply, error, state}
          end
        end
    end
  end

  @impl true
  def handle_call({:resolve_dispute, dispute_id}, _from, state) do
    # Implement Optimism's fault dispute game resolution
    case resolve_fault_dispute_game(dispute_id, state) do
      {:ok, :defender_wins} ->
        Logger.info("Dispute #{dispute_id} resolved: defender wins")
        {:reply, {:ok, :defender_wins}, state}

      {:ok, :challenger_wins} ->
        Logger.warn("Dispute #{dispute_id} resolved: challenger wins")
        # Trigger appropriate actions for successful challenge
        {:reply, {:ok, :challenger_wins}, state}

      {:error, reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_info(:check_challenge_expiry, state) do
    now = DateTime.utc_now()

    expired_challenges =
      state.challenges
      |> Enum.filter(fn {_id, challenge} ->
        challenge.status == :pending and
          DateTime.compare(now, challenge.expires_at) == :gt
      end)
      |> Enum.map(fn {id, challenge} -> {id, %{challenge | status: :expired}} end)
      |> Map.new()

    if map_size(expired_challenges) > 0 do
      Logger.info("Expired #{map_size(expired_challenges)} challenges")
      new_challenges = Map.merge(state.challenges, expired_challenges)

      # Return bonds to defenders for expired challenges
      Enum.each(expired_challenges, fn {_id, challenge} ->
        return_bond(challenge)
      end)

      Process.send_after(self(), :check_challenge_expiry, 60_000)
      {:noreply, %{state | challenges: new_challenges}}
    else
      Process.send_after(self(), :check_challenge_expiry, 60_000)
      {:noreply, state}
    end
  end

  # Private Functions

  defp via_tuple(rollup_id) do
    {:via, Registry, {ExWire.Layer2.OptimisticRegistry, rollup_id}}
  end

  defp generate_challenge_id() do
    "challenge_" <> Base.encode16(:crypto.strong_rand_bytes(16))
  end

  defp generate_withdrawal_id() do
    "withdrawal_" <> Base.encode16(:crypto.strong_rand_bytes(16))
  end

  defp get_caller_address() do
    # TODO: Get actual caller address from transaction context
    <<0::160>>
  end

  defp calculate_challenge_bond() do
    # TODO: Calculate appropriate bond amount
    # This should be based on network parameters
    %{
      # 1 ETH in wei
      amount: 1_000_000_000_000_000_000,
      token: :eth
    }
  end

  defp verify_fraud_proof(challenge, proof) do
    # Delegate to fraud proof verifier
    FraudProof.verify(challenge, proof)
  end

  defp rollback_state(rollup_id, batch_number) do
    # Rollback the rollup state to before the fraudulent batch
    Logger.warn("Rolling back state for rollup #{rollup_id} to before batch #{batch_number}")

    # TODO: Implement actual state rollback
    # - Remove invalid batches
    # - Recalculate state roots
    # - Emit rollback events

    :ok
  end

  defp slash_proposer(challenge) do
    # Slash the proposer who submitted the fraudulent state
    Logger.warn("Slashing proposer for fraudulent batch #{challenge.batch_number}")

    # TODO: Implement slashing logic
    # - Transfer bond to challenger
    # - Mark proposer as slashed
    # - Emit slashing event

    :ok
  end

  defp return_bond(challenge) do
    # Return bond to defender when challenge expires
    Logger.info("Returning bond for expired challenge #{challenge.id}")

    # TODO: Implement bond return
    :ok
  end

  defp emit_challenge_event(challenge) do
    # Emit event for monitoring and indexing
    Logger.debug("Challenge event: #{inspect(challenge)}")

    # TODO: Emit to event bus
    :ok
  end

  defp process_l1_withdrawal(withdrawal) do
    # Process the withdrawal on L1
    Logger.info("Processing L1 withdrawal: #{withdrawal.id}")

    # TODO: Implement L1 withdrawal processing
    # - Verify merkle proof
    # - Check withdrawal hasn't been processed
    # - Execute withdrawal on L1

    :ok
  end

  defp resolve_fault_dispute_game(dispute_id, state) do
    # Implement Optimism's fault dispute game resolution logic
    # This involves multiple rounds of bisection and instruction stepping

    # TODO: Implement full dispute game logic
    # For now, return a simulated result
    {:ok, Enum.random([:defender_wins, :challenger_wins])}
  end
end
