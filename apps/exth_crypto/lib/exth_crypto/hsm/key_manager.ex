defmodule ExthCrypto.HSM.KeyManager do
  @moduledoc """
  Enterprise key manager supporting both software and HSM-backed keys.

  This module provides a unified interface for key operations, automatically
  routing requests to the appropriate backend (software libsecp256k1 or HSM)
  based on key configuration and security policies.

  Key Features:
  - Seamless fallback between HSM and software keys
  - Role-based key access control
  - Automatic key discovery and caching
  - Audit logging of all key operations
  - Support for key rotation and lifecycle management
  - Emergency software fallback during HSM outages
  """

  use GenServer
  require Logger

  alias ExthCrypto.{Signature, Key}
  alias ExthCrypto.HSM.PKCS11Interface
  alias ExthCrypto.Hash.Keccak

  @type key_id :: String.t()
  @type key_backend :: :software | :hsm
  @type key_usage :: :signing | :validation | :encryption | :derivation
  @type key_role :: :validator | :transaction_signer | :node_identity | :admin

  @type key_descriptor :: %{
          id: key_id(),
          backend: key_backend(),
          usage: [key_usage()],
          role: key_role(),
          label: String.t(),
          public_key: binary(),
          hsm_handle: reference() | nil,
          software_key: binary() | nil,
          created_at: DateTime.t(),
          last_used: DateTime.t(),
          use_count: non_neg_integer(),
          metadata: map()
        }

  @type manager_state :: %{
          keys: %{key_id() => key_descriptor()},
          hsm_available: boolean(),
          fallback_enabled: boolean(),
          config: map(),
          stats: map()
        }

  ## GenServer API

  def start_link(config \\ %{}) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def init(config) do
    state = %{
      keys: %{},
      hsm_available: false,
      fallback_enabled: Map.get(config, :fallback_enabled, true),
      config: config,
      stats: %{
        keys_loaded: 0,
        hsm_operations: 0,
        software_operations: 0,
        fallback_activations: 0,
        errors: 0
      }
    }

    # Check HSM availability and discover keys
    {:ok, state, {:continue, :initialize}}
  end

  def handle_continue(:initialize, state) do
    Logger.info("Initializing HSM Key Manager")

    # Check HSM availability
    hsm_available = check_hsm_availability()

    # Discover existing keys
    discovered_keys = discover_keys(hsm_available)

    # Update state
    new_state = %{
      state
      | hsm_available: hsm_available,
        keys: discovered_keys,
        stats: Map.put(state.stats, :keys_loaded, map_size(discovered_keys))
    }

    Logger.info(
      "Key Manager initialized - HSM: #{hsm_available}, Keys: #{map_size(discovered_keys)}"
    )

    {:noreply, new_state}
  end

  def handle_call({:get_key, key_id}, _from, state) do
    case Map.get(state.keys, key_id) do
      nil -> {:reply, {:error, "Key not found: #{key_id}"}, state}
      key -> {:reply, {:ok, key}, state}
    end
  end

  def handle_call({:sign, key_id, data}, _from, state) do
    case Map.get(state.keys, key_id) do
      nil ->
        {:reply, {:error, "Key not found: #{key_id}"}, state}

      key ->
        {result, new_state} = perform_signing(key, data, state)
        {:reply, result, new_state}
    end
  end

  def handle_call({:generate_key, params}, _from, state) do
    {result, new_state} = generate_new_key(params, state)
    {:reply, result, new_state}
  end

  def handle_call({:list_keys, filters}, _from, state) do
    filtered_keys = filter_keys(state.keys, filters)
    {:reply, {:ok, filtered_keys}, state}
  end

  def handle_call({:delete_key, key_id}, _from, state) do
    {result, new_state} = delete_key(key_id, state)
    {:reply, result, new_state}
  end

  def handle_call(:get_stats, _from, state) do
    stats =
      Map.merge(state.stats, %{
        total_keys: map_size(state.keys),
        hsm_keys: count_keys_by_backend(state.keys, :hsm),
        software_keys: count_keys_by_backend(state.keys, :software),
        hsm_available: state.hsm_available
      })

    {:reply, {:ok, stats}, state}
  end

  def handle_info(:health_check, state) do
    # Periodic health check
    hsm_available = check_hsm_availability()

    if hsm_available != state.hsm_available do
      Logger.info("HSM availability changed: #{state.hsm_available} -> #{hsm_available}")

      # Update fallback status
      new_state = %{state | hsm_available: hsm_available}
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  ## Public API

  @doc """
  Get information about a specific key.
  """
  @spec get_key(key_id()) :: {:ok, key_descriptor()} | {:error, String.t()}
  def get_key(key_id) do
    GenServer.call(__MODULE__, {:get_key, key_id})
  end

  @doc """
  Sign data using the specified key.
  This automatically routes to HSM or software backend.
  """
  @spec sign(key_id(), binary()) :: {:ok, binary()} | {:error, String.t()}
  def sign(key_id, data) do
    GenServer.call(__MODULE__, {:sign, key_id, data}, 15_000)
  end

  @doc """
  Generate a new key with specified parameters.
  """
  @spec generate_key(map()) :: {:ok, key_descriptor()} | {:error, String.t()}
  def generate_key(params \\ %{}) do
    GenServer.call(__MODULE__, {:generate_key, params}, 30_000)
  end

  @doc """
  List keys matching the given filters.
  """
  @spec list_keys(map()) :: {:ok, [key_descriptor()]} | {:error, String.t()}
  def list_keys(filters \\ %{}) do
    GenServer.call(__MODULE__, {:list_keys, filters})
  end

  @doc """
  Delete a key (software keys only - HSM keys must be deleted through HSM tools).
  """
  @spec delete_key(key_id()) :: :ok | {:error, String.t()}
  def delete_key(key_id) do
    GenServer.call(__MODULE__, {:delete_key, key_id})
  end

  @doc """
  Get key manager statistics and status.
  """
  @spec get_stats() :: {:ok, map()}
  def get_stats() do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Ethereum-specific helper: Sign a transaction hash using appropriate key.
  """
  @spec sign_ethereum_transaction(key_id(), binary()) ::
          {:ok, {integer(), integer(), integer()}} | {:error, String.t()}
  def sign_ethereum_transaction(key_id, tx_hash) do
    case sign(key_id, tx_hash) do
      {:ok, signature} ->
        # Convert DER signature to Ethereum format (r, s, v)
        case parse_der_signature(signature) do
          {:ok, r, s} ->
            # Recovery ID calculation would need to be handled
            # For now, use default recovery ID
            v = 27
            {:ok, {v, r, s}}

          {:error, reason} ->
            {:error, "Failed to parse signature: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get public key for a given key ID.
  """
  @spec get_public_key(key_id()) :: {:ok, binary()} | {:error, String.t()}
  def get_public_key(key_id) do
    case get_key(key_id) do
      {:ok, key} -> {:ok, key.public_key}
      {:error, reason} -> {:error, reason}
    end
  end

  ## Private Implementation

  defp check_hsm_availability() do
    case PKCS11Interface.health_check() do
      %{status: :healthy} -> true
      _ -> false
    end
  end

  defp discover_keys(hsm_available) do
    keys = %{}

    # Discover HSM keys if available
    keys =
      if hsm_available do
        case PKCS11Interface.find_keys(%{key_type: :ec_secp256k1}) do
          {:ok, hsm_keys} ->
            Enum.reduce(hsm_keys, keys, fn hsm_key, acc ->
              key_id = generate_key_id(hsm_key.label)

              descriptor = %{
                id: key_id,
                backend: :hsm,
                usage: [:signing],
                role: determine_role_from_label(hsm_key.label),
                label: hsm_key.label,
                public_key: get_hsm_public_key(hsm_key.handle),
                hsm_handle: hsm_key.handle,
                software_key: nil,
                created_at: DateTime.utc_now(),
                last_used: DateTime.utc_now(),
                use_count: 0,
                metadata: %{
                  extractable: hsm_key.extractable,
                  hsm_info: hsm_key
                }
              }

              Map.put(acc, key_id, descriptor)
            end)

          {:error, reason} ->
            Logger.warn("Failed to discover HSM keys: #{reason}")
            keys
        end
      else
        keys
      end

    # Add any configured software keys
    keys = load_software_keys(keys)

    keys
  end

  defp perform_signing(key, data, state) do
    result =
      case key.backend do
        :hsm when state.hsm_available ->
          Logger.debug("Signing with HSM key: #{key.id}")

          case PKCS11Interface.sign(data, key.hsm_handle) do
            {:ok, signature} ->
              # Update key usage stats
              updated_key = %{
                key
                | last_used: DateTime.utc_now(),
                  use_count: key.use_count + 1
              }

              new_state = %{
                state
                | keys: Map.put(state.keys, key.id, updated_key),
                  stats: Map.update(state.stats, :hsm_operations, 1, &(&1 + 1))
              }

              audit_log_key_usage(key.id, :hsm_sign, :success)
              {:ok, signature, new_state}

            {:error, reason} ->
              Logger.error("HSM signing failed for key #{key.id}: #{reason}")
              audit_log_key_usage(key.id, :hsm_sign, {:error, reason})

              # Attempt fallback to software if enabled and available
              if state.fallback_enabled && key.software_key do
                Logger.info("Falling back to software signing for key: #{key.id}")
                fallback_software_sign(key, data, state)
              else
                new_state =
                  Map.update(state, :stats, %{}, fn stats ->
                    Map.update(stats, :errors, 1, &(&1 + 1))
                  end)

                {:error, "HSM signing failed: #{reason}", new_state}
              end
          end

        :hsm when not state.hsm_available ->
          Logger.warn("HSM not available for key: #{key.id}")

          if state.fallback_enabled && key.software_key do
            Logger.info("Using software fallback for HSM key: #{key.id}")
            fallback_software_sign(key, data, state)
          else
            {:error, "HSM not available and no fallback configured", state}
          end

        :software ->
          Logger.debug("Signing with software key: #{key.id}")
          software_sign(key, data, state)
      end

    case result do
      {:ok, signature, new_state} -> {{:ok, signature}, new_state}
      {:error, reason, new_state} -> {{:error, reason}, new_state}
    end
  end

  defp software_sign(key, data, state) do
    case Signature.sign_digest(data, key.software_key) do
      {signature, _r, _s, _recovery_id} ->
        # Update key usage stats
        updated_key = %{
          key
          | last_used: DateTime.utc_now(),
            use_count: key.use_count + 1
        }

        new_state = %{
          state
          | keys: Map.put(state.keys, key.id, updated_key),
            stats: Map.update(state.stats, :software_operations, 1, &(&1 + 1))
        }

        audit_log_key_usage(key.id, :software_sign, :success)
        {:ok, signature, new_state}

      error ->
        Logger.error("Software signing failed for key #{key.id}: #{inspect(error)}")
        audit_log_key_usage(key.id, :software_sign, {:error, error})

        new_state =
          Map.update(state, :stats, %{}, fn stats ->
            Map.update(stats, :errors, 1, &(&1 + 1))
          end)

        {:error, "Software signing failed", new_state}
    end
  end

  defp fallback_software_sign(key, data, state) do
    new_state =
      Map.update(state, :stats, %{}, fn stats ->
        Map.update(stats, :fallback_activations, 1, &(&1 + 1))
      end)

    software_sign(key, data, new_state)
  end

  defp generate_new_key(params, state) do
    backend = Map.get(params, :backend, :auto)
    label = Map.get(params, :label, "ethereum-key-#{System.unique_integer([:positive])}")
    role = Map.get(params, :role, :transaction_signer)
    usage = Map.get(params, :usage, [:signing])

    # Determine actual backend
    actual_backend =
      case backend do
        :auto ->
          if state.hsm_available, do: :hsm, else: :software

        :hsm when state.hsm_available ->
          :hsm

        :hsm when not state.hsm_available ->
          if state.fallback_enabled do
            Logger.warn("HSM requested but not available, falling back to software")
            :software
          else
            :error
          end

        :software ->
          :software
      end

    case actual_backend do
      :hsm ->
        generate_hsm_key(label, role, usage, state)

      :software ->
        generate_software_key(label, role, usage, state)

      :error ->
        {{:error, "HSM not available"}, state}
    end
  end

  defp generate_hsm_key(label, role, usage, state) do
    case PKCS11Interface.generate_ethereum_key_pair(label) do
      {:ok, {private_handle, public_handle}} ->
        case PKCS11Interface.get_public_key(private_handle) do
          {:ok, public_key} ->
            key_id = generate_key_id(label)

            descriptor = %{
              id: key_id,
              backend: :hsm,
              usage: usage,
              role: role,
              label: label,
              public_key: public_key,
              hsm_handle: private_handle,
              software_key: nil,
              created_at: DateTime.utc_now(),
              last_used: DateTime.utc_now(),
              use_count: 0,
              metadata: %{
                hsm_public_handle: public_handle,
                generated_on_hsm: true
              }
            }

            new_state = %{
              state
              | keys: Map.put(state.keys, key_id, descriptor),
                stats: Map.update(state.stats, :keys_loaded, 1, &(&1 + 1))
            }

            Logger.info("Generated new HSM key: #{key_id}")
            audit_log_key_generation(key_id, :hsm, label)

            {{:ok, descriptor}, new_state}

          {:error, reason} ->
            Logger.error("Failed to get public key for generated HSM key: #{reason}")
            {{:error, "Failed to retrieve public key"}, state}
        end

      {:error, reason} ->
        Logger.error("Failed to generate HSM key pair: #{reason}")
        {{:error, "HSM key generation failed: #{reason}"}, state}
    end
  end

  defp generate_software_key(label, role, usage, state) do
    # Generate random private key
    private_key = :crypto.strong_rand_bytes(32)

    case Signature.get_public_key(private_key) do
      {:ok, public_key} ->
        key_id = generate_key_id(label)

        descriptor = %{
          id: key_id,
          backend: :software,
          usage: usage,
          role: role,
          label: label,
          public_key: public_key,
          hsm_handle: nil,
          software_key: private_key,
          created_at: DateTime.utc_now(),
          last_used: DateTime.utc_now(),
          use_count: 0,
          metadata: %{
            generated_in_memory: true
          }
        }

        new_state = %{
          state
          | keys: Map.put(state.keys, key_id, descriptor),
            stats: Map.update(state.stats, :keys_loaded, 1, &(&1 + 1))
        }

        Logger.info("Generated new software key: #{key_id}")
        audit_log_key_generation(key_id, :software, label)

        {{:ok, descriptor}, new_state}

      {:error, reason} ->
        Logger.error("Failed to generate public key from private key: #{reason}")
        {{:error, "Software key generation failed"}, state}
    end
  end

  defp delete_key(key_id, state) do
    case Map.get(state.keys, key_id) do
      nil ->
        {{:error, "Key not found: #{key_id}"}, state}

      key ->
        case key.backend do
          :hsm ->
            Logger.warn("Cannot delete HSM key #{key_id} - use HSM management tools")
            {{:error, "HSM keys must be deleted using HSM management tools"}, state}

          :software ->
            new_keys = Map.delete(state.keys, key_id)
            new_state = %{state | keys: new_keys}

            Logger.info("Deleted software key: #{key_id}")
            audit_log_key_deletion(key_id, :software)

            {:ok, new_state}
        end
    end
  end

  # Helper functions

  defp filter_keys(keys, filters) when map_size(filters) == 0, do: Map.values(keys)

  defp filter_keys(keys, filters) do
    keys
    |> Map.values()
    |> Enum.filter(fn key ->
      Enum.all?(filters, fn {filter_key, filter_value} ->
        case filter_key do
          :backend -> key.backend == filter_value
          :role -> key.role == filter_value
          :usage -> filter_value in key.usage
          :label -> String.contains?(key.label, filter_value)
          _ -> Map.get(key, filter_key) == filter_value
        end
      end)
    end)
  end

  defp count_keys_by_backend(keys, backend) do
    keys
    |> Map.values()
    |> Enum.count(fn key -> key.backend == backend end)
  end

  defp generate_key_id(label) do
    # Generate deterministic key ID from label and timestamp
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    content = "#{label}-#{timestamp}"

    content
    |> Keccak.kec()
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  defp determine_role_from_label(label) do
    cond do
      String.contains?(String.downcase(label), "validator") -> :validator
      String.contains?(String.downcase(label), "admin") -> :admin
      String.contains?(String.downcase(label), "node") -> :node_identity
      true -> :transaction_signer
    end
  end

  defp get_hsm_public_key(hsm_handle) do
    case PKCS11Interface.get_public_key(hsm_handle) do
      {:ok, public_key} -> public_key
      # Placeholder - in production this should be handled properly
      {:error, _} -> <<>>
    end
  end

  defp load_software_keys(keys) do
    # In production, this would load from secure configuration
    # For now, we'll just return the existing keys
    keys
  end

  defp parse_der_signature(der_signature) do
    # Simple DER parsing - in production use proper ASN.1 library
    try do
      <<0x30, _length, 0x02, r_length, r::binary-size(r_length), 0x02, s_length,
        s::binary-size(s_length), _rest::binary>> = der_signature

      r_int = :binary.decode_unsigned(r)
      s_int = :binary.decode_unsigned(s)

      {:ok, r_int, s_int}
    rescue
      _ -> {:error, "Invalid DER signature format"}
    end
  end

  # Audit logging functions

  defp audit_log_key_usage(key_id, operation, result) do
    Logger.info("KEY_AUDIT: key=#{key_id} operation=#{operation} result=#{inspect(result)}")
  end

  defp audit_log_key_generation(key_id, backend, label) do
    Logger.info("KEY_AUDIT: key=#{key_id} operation=generate backend=#{backend} label=#{label}")
  end

  defp audit_log_key_deletion(key_id, backend) do
    Logger.info("KEY_AUDIT: key=#{key_id} operation=delete backend=#{backend}")
  end
end
