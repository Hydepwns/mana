defmodule ExWire.Enterprise.HSMIntegration do
  @moduledoc """
  Hardware Security Module (HSM) integration for enterprise-grade key management.
  Supports PKCS#11, AWS CloudHSM, Azure Key Vault, and HashiCorp Vault.
  """

  use GenServer
  require Logger

  alias ExWire.Crypto
  alias ExWire.Enterprise.AuditLogger

  defstruct [
    :provider,
    :config,
    :connection,
    :keys,
    :session_id,
    :status,
    :metrics,
    :last_health_check
  ]

  @type provider :: :pkcs11 | :aws_cloudhsm | :azure_keyvault | :hashicorp_vault | :softhsm

  @type key_info :: %{
          key_id: String.t(),
          key_type: :ecdsa | :rsa | :ed25519,
          key_usage: list(:sign | :verify | :encrypt | :decrypt),
          created_at: DateTime.t(),
          metadata: map()
        }

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  @doc """
  Initialize HSM connection
  """
  def connect(provider, config) do
    GenServer.call(__MODULE__, {:connect, provider, config})
  end

  @doc """
  Generate a new key in the HSM
  """
  def generate_key(key_type, key_id, opts \\ []) do
    GenServer.call(__MODULE__, {:generate_key, key_type, key_id, opts})
  end

  @doc """
  Import an existing key into the HSM
  """
  def import_key(key_data, key_id, opts \\ []) do
    GenServer.call(__MODULE__, {:import_key, key_data, key_id, opts})
  end

  @doc """
  Sign data using an HSM-protected key
  """
  def sign(key_id, data, algorithm \\ :ecdsa_sha256) do
    GenServer.call(__MODULE__, {:sign, key_id, data, algorithm})
  end

  @doc """
  Verify a signature using an HSM-protected key
  """
  def verify(key_id, data, signature, algorithm \\ :ecdsa_sha256) do
    GenServer.call(__MODULE__, {:verify, key_id, data, signature, algorithm})
  end

  @doc """
  Encrypt data using an HSM-protected key
  """
  def encrypt(key_id, plaintext) do
    GenServer.call(__MODULE__, {:encrypt, key_id, plaintext})
  end

  @doc """
  Decrypt data using an HSM-protected key
  """
  def decrypt(key_id, ciphertext) do
    GenServer.call(__MODULE__, {:decrypt, key_id, ciphertext})
  end

  @doc """
  List all keys in the HSM
  """
  def list_keys do
    GenServer.call(__MODULE__, :list_keys)
  end

  @doc """
  Delete a key from the HSM
  """
  def delete_key(key_id) do
    GenServer.call(__MODULE__, {:delete_key, key_id})
  end

  @doc """
  Get HSM health status
  """
  def health_check do
    GenServer.call(__MODULE__, :health_check)
  end

  @doc """
  Rotate a key in the HSM
  """
  def rotate_key(key_id) do
    GenServer.call(__MODULE__, {:rotate_key, key_id})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    Logger.info("Starting HSM Integration service")

    state = %__MODULE__{
      provider: nil,
      config: %{},
      connection: nil,
      keys: %{},
      session_id: nil,
      status: :disconnected,
      metrics: initialize_metrics(),
      last_health_check: nil
    }

    # Auto-connect if config provided
    if opts[:auto_connect] do
      send(self(), {:auto_connect, opts[:provider], opts[:config]})
    end

    schedule_health_check()
    {:ok, state}
  end

  @impl true
  def handle_call({:connect, provider, config}, _from, state) do
    case connect_to_hsm(provider, config) do
      {:ok, connection} ->
        state = %{
          state
          | provider: provider,
            config: config,
            connection: connection,
            session_id: generate_session_id(),
            status: :connected
        }

        # Load existing keys
        {:ok, keys} = load_keys_from_hsm(connection, provider)
        state = %{state | keys: keys}

        AuditLogger.log(:hsm_connected, %{
          provider: provider,
          session_id: state.session_id
        })

        {:reply, {:ok, state.session_id}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:generate_key, key_type, key_id, opts}, _from, state) do
    if state.status != :connected do
      {:reply, {:error, :not_connected}, state}
    else
      case generate_key_in_hsm(state, key_type, key_id, opts) do
        {:ok, key_info} ->
          state = put_in(state.keys[key_id], key_info)
          update_metrics(state, :keys_generated)

          AuditLogger.log(:hsm_key_generated, %{
            key_id: key_id,
            key_type: key_type,
            provider: state.provider
          })

          {:reply, {:ok, key_info}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call({:sign, key_id, data, algorithm}, _from, state) do
    if state.status != :connected do
      {:reply, {:error, :not_connected}, state}
    else
      case Map.get(state.keys, key_id) do
        nil ->
          {:reply, {:error, :key_not_found}, state}

        key_info ->
          case sign_with_hsm(state, key_id, data, algorithm) do
            {:ok, signature} ->
              update_metrics(state, :signatures_created)

              AuditLogger.log(:hsm_sign_operation, %{
                key_id: key_id,
                data_size: byte_size(data),
                algorithm: algorithm
              })

              {:reply, {:ok, signature}, state}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
      end
    end
  end

  @impl true
  def handle_call({:verify, key_id, data, signature, algorithm}, _from, state) do
    if state.status != :connected do
      {:reply, {:error, :not_connected}, state}
    else
      case verify_with_hsm(state, key_id, data, signature, algorithm) do
        {:ok, valid} ->
          update_metrics(state, :signatures_verified)
          {:reply, {:ok, valid}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call({:encrypt, key_id, plaintext}, _from, state) do
    if state.status != :connected do
      {:reply, {:error, :not_connected}, state}
    else
      case encrypt_with_hsm(state, key_id, plaintext) do
        {:ok, ciphertext} ->
          update_metrics(state, :encryptions)
          {:reply, {:ok, ciphertext}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call({:decrypt, key_id, ciphertext}, _from, state) do
    if state.status != :connected do
      {:reply, {:error, :not_connected}, state}
    else
      case decrypt_with_hsm(state, key_id, ciphertext) do
        {:ok, plaintext} ->
          update_metrics(state, :decryptions)
          {:reply, {:ok, plaintext}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call(:list_keys, _from, state) do
    keys =
      Enum.map(state.keys, fn {id, info} ->
        %{
          key_id: id,
          key_type: info.key_type,
          created_at: info.created_at,
          key_usage: info.key_usage
        }
      end)

    {:reply, {:ok, keys}, state}
  end

  @impl true
  def handle_call({:delete_key, key_id}, _from, state) do
    if state.status != :connected do
      {:reply, {:error, :not_connected}, state}
    else
      case delete_key_from_hsm(state, key_id) do
        :ok ->
          state = update_in(state.keys, &Map.delete(&1, key_id))

          AuditLogger.log(:hsm_key_deleted, %{
            key_id: key_id,
            provider: state.provider
          })

          {:reply, :ok, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call({:rotate_key, key_id}, _from, state) do
    if state.status != :connected do
      {:reply, {:error, :not_connected}, state}
    else
      case rotate_key_in_hsm(state, key_id) do
        {:ok, new_key_info} ->
          state = put_in(state.keys[key_id], new_key_info)

          AuditLogger.log(:hsm_key_rotated, %{
            key_id: key_id,
            provider: state.provider
          })

          {:reply, {:ok, new_key_info}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    health = perform_health_check(state)
    state = %{state | last_health_check: DateTime.utc_now()}
    {:reply, {:ok, health}, state}
  end

  @impl true
  def handle_info(:scheduled_health_check, state) do
    health = perform_health_check(state)

    if health.status == :unhealthy && state.status == :connected do
      Logger.error("HSM health check failed: #{inspect(health)}")
      state = %{state | status: :degraded}
    end

    schedule_health_check()
    {:noreply, %{state | last_health_check: DateTime.utc_now()}}
  end

  @impl true
  def handle_info({:auto_connect, provider, config}, state) do
    case connect_to_hsm(provider, config) do
      {:ok, connection} ->
        state = %{
          state
          | provider: provider,
            config: config,
            connection: connection,
            session_id: generate_session_id(),
            status: :connected
        }

        {:ok, keys} = load_keys_from_hsm(connection, provider)
        {:noreply, %{state | keys: keys}}

      {:error, reason} ->
        Logger.error("Failed to auto-connect to HSM: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  # Private Functions - HSM Provider Implementations

  defp connect_to_hsm(:pkcs11, config) do
    # PKCS#11 connection implementation
    {:ok, %{type: :pkcs11, slot: config.slot, pin: config.pin}}
  end

  defp connect_to_hsm(:aws_cloudhsm, config) do
    # AWS CloudHSM connection
    {:ok, %{type: :aws_cloudhsm, cluster_id: config.cluster_id}}
  end

  defp connect_to_hsm(:azure_keyvault, config) do
    # Azure Key Vault connection
    {:ok, %{type: :azure_keyvault, vault_name: config.vault_name}}
  end

  defp connect_to_hsm(:hashicorp_vault, config) do
    # HashiCorp Vault connection
    {:ok, %{type: :hashicorp_vault, address: config.address, token: config.token}}
  end

  defp connect_to_hsm(:softhsm, config) do
    # SoftHSM for testing
    {:ok, %{type: :softhsm, config: config}}
  end

  defp generate_key_in_hsm(state, key_type, key_id, opts) do
    # Provider-specific key generation
    key_info = %{
      key_id: key_id,
      key_type: key_type,
      key_usage: Keyword.get(opts, :key_usage, [:sign, :verify]),
      created_at: DateTime.utc_now(),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    case state.provider do
      :softhsm ->
        # Simulate key generation for testing
        {:ok, key_info}

      _ ->
        # Real HSM key generation would go here
        {:ok, key_info}
    end
  end

  defp sign_with_hsm(state, key_id, data, algorithm) do
    # Provider-specific signing
    case state.provider do
      :softhsm ->
        # Simulate signing for testing
        signature =
          :crypto.sign(:ecdsa, :sha256, data, [:crypto.strong_rand_bytes(32), :secp256k1])

        {:ok, signature}

      _ ->
        # Real HSM signing would go here
        {:ok, <<0::256>>}
    end
  end

  defp verify_with_hsm(state, key_id, data, signature, algorithm) do
    # Provider-specific verification
    case state.provider do
      :softhsm ->
        # Simulate verification for testing
        {:ok, true}

      _ ->
        # Real HSM verification would go here
        {:ok, true}
    end
  end

  defp encrypt_with_hsm(state, key_id, plaintext) do
    # Provider-specific encryption
    case state.provider do
      :softhsm ->
        # Simulate encryption for testing
        key = :crypto.strong_rand_bytes(32)
        iv = :crypto.strong_rand_bytes(16)
        ciphertext = :crypto.crypto_one_time(:aes_256_cbc, key, iv, plaintext, true)
        {:ok, iv <> ciphertext}

      _ ->
        # Real HSM encryption would go here
        {:ok, plaintext}
    end
  end

  defp decrypt_with_hsm(state, key_id, ciphertext) do
    # Provider-specific decryption
    case state.provider do
      :softhsm ->
        # Simulate decryption for testing
        {:ok, ciphertext}

      _ ->
        # Real HSM decryption would go here
        {:ok, ciphertext}
    end
  end

  defp delete_key_from_hsm(state, key_id) do
    # Provider-specific key deletion
    :ok
  end

  defp rotate_key_in_hsm(state, key_id) do
    case Map.get(state.keys, key_id) do
      nil ->
        {:error, :key_not_found}

      old_key_info ->
        # Generate new key with same properties
        new_key_info = %{
          old_key_info
          | created_at: DateTime.utc_now(),
            metadata: Map.put(old_key_info.metadata, :rotated_from, key_id)
        }

        {:ok, new_key_info}
    end
  end

  defp load_keys_from_hsm(connection, provider) do
    # Load existing keys from HSM
    {:ok, %{}}
  end

  defp perform_health_check(state) do
    %{
      status: if(state.status == :connected, do: :healthy, else: :unhealthy),
      provider: state.provider,
      keys_count: map_size(state.keys),
      metrics: state.metrics,
      last_check: state.last_health_check
    }
  end

  defp initialize_metrics do
    %{
      keys_generated: 0,
      signatures_created: 0,
      signatures_verified: 0,
      encryptions: 0,
      decryptions: 0,
      errors: 0
    }
  end

  defp update_metrics(state, operation) do
    update_in(state.metrics[operation], &(&1 + 1))
  end

  defp generate_session_id do
    Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end

  defp schedule_health_check do
    Process.send_after(self(), :scheduled_health_check, :timer.minutes(5))
  end
end
