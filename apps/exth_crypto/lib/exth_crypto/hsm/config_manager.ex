defmodule ExthCrypto.HSM.ConfigManager do
  @moduledoc """
  Configuration management for HSM integration.

  This module handles all HSM-related configuration including:
  - HSM connection parameters
  - Security policies and key usage rules
  - Fallback behavior configuration
  - Performance and monitoring settings
  - Integration with Mix configuration and runtime configuration
  """

  use GenServer
  require Logger

  @type hsm_vendor :: :thales | :aws_cloudhsm | :safenet_luna | :utimaco | :yubihsm | :softhsm

  @type hsm_config :: %{
          enabled: boolean(),
          vendor: hsm_vendor(),
          library_path: String.t(),
          slot_id: non_neg_integer(),
          pin: String.t() | nil,
          token_label: String.t(),
          connection_pool: pool_config(),
          security_policy: security_policy(),
          fallback: fallback_config(),
          monitoring: monitoring_config()
        }

  @type pool_config :: %{
          size: non_neg_integer(),
          max_overflow: non_neg_integer(),
          timeout: non_neg_integer(),
          idle_timeout: non_neg_integer()
        }

  @type security_policy :: %{
          require_hsm_for_roles: [atom()],
          allow_software_fallback: boolean(),
          max_signing_rate: non_neg_integer(),
          audit_all_operations: boolean(),
          key_generation_policy: key_generation_policy()
        }

  @type key_generation_policy :: %{
          default_backend: :hsm | :software | :auto,
          extractable_keys: boolean(),
          sensitive_keys: boolean(),
          key_size: non_neg_integer(),
          curve: :secp256k1
        }

  @type fallback_config :: %{
          enabled: boolean(),
          auto_fallback_on_error: boolean(),
          fallback_timeout: non_neg_integer(),
          max_fallback_operations: non_neg_integer()
        }

  @type monitoring_config :: %{
          health_check_interval: non_neg_integer(),
          performance_monitoring: boolean(),
          alert_on_fallback: boolean(),
          alert_on_errors: boolean(),
          metrics_retention: non_neg_integer()
        }

  # Default configurations for different HSM vendors
  @vendor_defaults %{
    thales: %{
      library_path: "/opt/nfast/toolkits/pkcs11/libcknfast.so",
      slot_id: 0,
      connection_pool: %{size: 5, max_overflow: 10, timeout: 30_000, idle_timeout: 60_000}
    },
    aws_cloudhsm: %{
      library_path: "/opt/cloudhsm/lib/libcloudhsm_pkcs11.so",
      slot_id: 0,
      connection_pool: %{size: 10, max_overflow: 20, timeout: 15_000, idle_timeout: 30_000}
    },
    safenet_luna: %{
      library_path: "/usr/safenet/lunaclient/lib/libCryptoki2_64.so",
      slot_id: 0,
      connection_pool: %{size: 8, max_overflow: 16, timeout: 20_000, idle_timeout: 45_000}
    },
    utimaco: %{
      library_path: "/opt/utimaco/lib/libcs_pkcs11_R2.so",
      slot_id: 0,
      connection_pool: %{size: 6, max_overflow: 12, timeout: 25_000, idle_timeout: 50_000}
    },
    yubihsm: %{
      library_path: "/usr/local/lib/pkcs11/yubihsm_pkcs11.so",
      slot_id: 0,
      connection_pool: %{size: 3, max_overflow: 6, timeout: 10_000, idle_timeout: 20_000}
    },
    softhsm: %{
      library_path: "/usr/lib/x86_64-linux-gnu/softhsm/libsofthsm2.so",
      slot_id: 0,
      connection_pool: %{size: 4, max_overflow: 8, timeout: 5_000, idle_timeout: 15_000}
    }
  }

  # Default security policy
  @default_security_policy %{
    require_hsm_for_roles: [:validator, :admin],
    allow_software_fallback: true,
    # signatures per minute
    max_signing_rate: 1000,
    audit_all_operations: true,
    key_generation_policy: %{
      default_backend: :auto,
      extractable_keys: false,
      sensitive_keys: true,
      key_size: 256,
      curve: :secp256k1
    }
  }

  # Default fallback configuration
  @default_fallback %{
    enabled: true,
    auto_fallback_on_error: true,
    fallback_timeout: 5_000,
    max_fallback_operations: 100
  }

  # Default monitoring configuration
  @default_monitoring %{
    # 30 seconds
    health_check_interval: 30_000,
    performance_monitoring: true,
    alert_on_fallback: true,
    alert_on_errors: true,
    # 24 hours in seconds
    metrics_retention: 86_400
  }

  ## GenServer API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    config = load_configuration()

    state = %{
      config: config,
      last_updated: DateTime.utc_now(),
      validation_errors: [],
      runtime_overrides: %{}
    }

    case validate_configuration(config) do
      {:ok, validated_config} ->
        Logger.info("HSM Configuration loaded successfully")
        {:ok, %{state | config: validated_config}}

      {:error, errors} ->
        Logger.error("HSM Configuration validation failed: #{inspect(errors)}")
        {:ok, %{state | validation_errors: errors}}
    end
  end

  def handle_call(:get_config, _from, state) do
    config = apply_runtime_overrides(state.config, state.runtime_overrides)
    {:reply, {:ok, config}, state}
  end

  def handle_call({:update_config, updates}, _from, state) do
    case validate_configuration_updates(updates) do
      {:ok, validated_updates} ->
        new_config = deep_merge(state.config, validated_updates)

        new_state = %{
          state
          | config: new_config,
            last_updated: DateTime.utc_now()
        }

        Logger.info("HSM Configuration updated")
        {:reply, :ok, new_state}

      {:error, errors} ->
        {:reply, {:error, errors}, state}
    end
  end

  def handle_call({:set_runtime_override, key, value}, _from, state) do
    new_overrides = Map.put(state.runtime_overrides, key, value)
    new_state = %{state | runtime_overrides: new_overrides}

    Logger.info("HSM Runtime override set: #{key} = #{inspect(value)}")
    {:reply, :ok, new_state}
  end

  def handle_call({:remove_runtime_override, key}, _from, state) do
    new_overrides = Map.delete(state.runtime_overrides, key)
    new_state = %{state | runtime_overrides: new_overrides}

    Logger.info("HSM Runtime override removed: #{key}")
    {:reply, :ok, new_state}
  end

  def handle_call(:get_validation_errors, _from, state) do
    {:reply, state.validation_errors, state}
  end

  ## Public API

  @doc """
  Get the current HSM configuration.
  """
  @spec get_config() :: {:ok, hsm_config()} | {:error, String.t()}
  def get_config() do
    GenServer.call(__MODULE__, :get_config)
  end

  @doc """
  Update HSM configuration with new values.
  """
  @spec update_config(map()) :: :ok | {:error, [String.t()]}
  def update_config(updates) do
    GenServer.call(__MODULE__, {:update_config, updates})
  end

  @doc """
  Set a runtime configuration override (temporary, not persisted).
  """
  @spec set_runtime_override(String.t(), any()) :: :ok
  def set_runtime_override(key, value) do
    GenServer.call(__MODULE__, {:set_runtime_override, key, value})
  end

  @doc """
  Remove a runtime configuration override.
  """
  @spec remove_runtime_override(String.t()) :: :ok
  def remove_runtime_override(key) do
    GenServer.call(__MODULE__, {:remove_runtime_override, key})
  end

  @doc """
  Get any configuration validation errors.
  """
  @spec get_validation_errors() :: [String.t()]
  def get_validation_errors() do
    GenServer.call(__MODULE__, :get_validation_errors)
  end

  @doc """
  Check if HSM is enabled in the configuration.
  """
  @spec hsm_enabled?() :: boolean()
  def hsm_enabled?() do
    case get_config() do
      {:ok, config} -> config.enabled
      {:error, _} -> false
    end
  end

  @doc """
  Get HSM configuration for a specific component.
  """
  @spec get_component_config(atom()) :: {:ok, map()} | {:error, String.t()}
  def get_component_config(component) do
    case get_config() do
      {:ok, config} ->
        case component do
          :pkcs11 -> {:ok, extract_pkcs11_config(config)}
          :key_manager -> {:ok, extract_key_manager_config(config)}
          :signing_service -> {:ok, extract_signing_service_config(config)}
          :monitoring -> {:ok, config.monitoring}
          _ -> {:error, "Unknown component: #{component}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generate a sample configuration file for a specific HSM vendor.
  """
  @spec generate_sample_config(hsm_vendor()) :: String.t()
  def generate_sample_config(vendor)
      when vendor in [:thales, :aws_cloudhsm, :safenet_luna, :utimaco, :yubihsm, :softhsm] do
    vendor_config = @vendor_defaults[vendor]

    sample_config = %{
      hsm: %{
        enabled: true,
        vendor: vendor,
        library_path: vendor_config.library_path,
        slot_id: vendor_config.slot_id,
        pin: "REPLACE_WITH_YOUR_PIN",
        token_label: "ETHEREUM_TOKEN",
        connection_pool: vendor_config.connection_pool,
        security_policy: @default_security_policy,
        fallback: @default_fallback,
        monitoring: @default_monitoring
      }
    }

    case Jason.encode(sample_config, pretty: true) do
      {:ok, json} -> json
      {:error, _} -> "Failed to generate sample configuration"
    end
  end

  ## Private Implementation

  defp load_configuration() do
    # Load from Mix configuration
    base_config = Application.get_env(:exth_crypto, :hsm, %{})

    # Apply environment variable overrides
    env_config = load_from_environment()

    # Merge configurations with proper defaults
    merged_config = deep_merge(default_config(), deep_merge(base_config, env_config))

    # Apply vendor-specific defaults if vendor is specified
    if vendor = merged_config[:vendor] do
      vendor_defaults = @vendor_defaults[vendor] || %{}
      deep_merge(merged_config, vendor_defaults)
    else
      merged_config
    end
  end

  defp load_from_environment() do
    env_config = %{}

    # HSM_ENABLED
    env_config =
      if enabled = System.get_env("HSM_ENABLED") do
        Map.put(env_config, :enabled, String.downcase(enabled) == "true")
      else
        env_config
      end

    # HSM_VENDOR
    env_config =
      if vendor = System.get_env("HSM_VENDOR") do
        Map.put(env_config, :vendor, String.to_atom(vendor))
      else
        env_config
      end

    # HSM_LIBRARY_PATH
    env_config =
      if library_path = System.get_env("HSM_LIBRARY_PATH") do
        Map.put(env_config, :library_path, library_path)
      else
        env_config
      end

    # HSM_SLOT_ID
    env_config =
      if slot_id = System.get_env("HSM_SLOT_ID") do
        Map.put(env_config, :slot_id, String.to_integer(slot_id))
      else
        env_config
      end

    # HSM_PIN (from environment variable or file)
    env_config =
      if pin = System.get_env("HSM_PIN") do
        Map.put(env_config, :pin, pin)
      else
        if pin_file = System.get_env("HSM_PIN_FILE") do
          case File.read(pin_file) do
            {:ok, pin} -> Map.put(env_config, :pin, String.trim(pin))
            {:error, _} -> env_config
          end
        else
          env_config
        end
      end

    # HSM_TOKEN_LABEL
    env_config =
      if token_label = System.get_env("HSM_TOKEN_LABEL") do
        Map.put(env_config, :token_label, token_label)
      else
        env_config
      end

    env_config
  end

  defp default_config() do
    %{
      enabled: false,
      vendor: :softhsm,
      library_path: "/usr/lib/x86_64-linux-gnu/softhsm/libsofthsm2.so",
      slot_id: 0,
      pin: nil,
      token_label: "ETHEREUM_HSM",
      connection_pool: %{
        size: 5,
        max_overflow: 10,
        timeout: 30_000,
        idle_timeout: 60_000
      },
      security_policy: @default_security_policy,
      fallback: @default_fallback,
      monitoring: @default_monitoring
    }
  end

  defp validate_configuration(config) do
    errors = []

    # Validate basic required fields
    errors =
      if not is_boolean(config[:enabled]) do
        ["enabled must be a boolean" | errors]
      else
        errors
      end

    errors =
      if config[:enabled] do
        # Validate HSM-specific configuration when enabled
        errors =
          if not is_atom(config[:vendor]) or config[:vendor] not in Map.keys(@vendor_defaults) do
            ["vendor must be one of: #{inspect(Map.keys(@vendor_defaults))}" | errors]
          else
            errors
          end

        errors =
          if not is_binary(config[:library_path]) do
            ["library_path must be a string" | errors]
          else
            errors
          end

        errors =
          if not is_integer(config[:slot_id]) or config[:slot_id] < 0 do
            ["slot_id must be a non-negative integer" | errors]
          else
            errors
          end

        errors =
          if config[:pin] && not is_binary(config[:pin]) do
            ["pin must be a string or nil" | errors]
          else
            errors
          end

        # Validate that library file exists if it's a local path
        errors =
          if String.starts_with?(config[:library_path], "/") do
            if File.exists?(config[:library_path]) do
              errors
            else
              ["PKCS#11 library not found: #{config[:library_path]}" | errors]
            end
          else
            errors
          end

        # Validate connection pool configuration
        errors = validate_pool_config(config[:connection_pool], errors)

        # Validate security policy
        errors = validate_security_policy(config[:security_policy], errors)

        errors
      else
        errors
      end

    if Enum.empty?(errors) do
      {:ok, config}
    else
      {:error, errors}
    end
  end

  defp validate_configuration_updates(updates) do
    # Similar validation logic but for partial updates
    validate_configuration(updates)
  end

  defp validate_pool_config(pool_config, errors) do
    errors =
      if not is_integer(pool_config[:size]) or pool_config[:size] <= 0 do
        ["connection_pool.size must be a positive integer" | errors]
      else
        errors
      end

    errors =
      if not is_integer(pool_config[:max_overflow]) or pool_config[:max_overflow] < 0 do
        ["connection_pool.max_overflow must be a non-negative integer" | errors]
      else
        errors
      end

    errors =
      if not is_integer(pool_config[:timeout]) or pool_config[:timeout] <= 0 do
        ["connection_pool.timeout must be a positive integer" | errors]
      else
        errors
      end

    errors
  end

  defp validate_security_policy(security_policy, errors) do
    errors =
      if not is_list(security_policy[:require_hsm_for_roles]) do
        ["security_policy.require_hsm_for_roles must be a list" | errors]
      else
        errors
      end

    errors =
      if not is_boolean(security_policy[:allow_software_fallback]) do
        ["security_policy.allow_software_fallback must be a boolean" | errors]
      else
        errors
      end

    errors
  end

  defp extract_pkcs11_config(config) do
    %{
      library_path: config.library_path,
      slot_id: config.slot_id,
      pin: config.pin,
      label: config.token_label,
      read_write: true
    }
  end

  defp extract_key_manager_config(config) do
    %{
      fallback_enabled: config.fallback.enabled,
      security_policy: config.security_policy,
      audit_enabled: config.security_policy.audit_all_operations
    }
  end

  defp extract_signing_service_config(config) do
    %{
      prefer_hsm: config.security_policy.require_hsm_for_roles != [],
      fallback_enabled: config.fallback.enabled,
      max_concurrent_operations: config.connection_pool.size * 2,
      operation_timeout: config.connection_pool.timeout,
      audit_enabled: config.security_policy.audit_all_operations
    }
  end

  defp apply_runtime_overrides(config, overrides) do
    Enum.reduce(overrides, config, fn {key, value}, acc ->
      put_in(acc, [key], value)
    end)
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, &deep_resolve/3)
  end

  defp deep_resolve(_key, left, right) when is_map(left) and is_map(right) do
    deep_merge(left, right)
  end

  defp deep_resolve(_key, _left, right) do
    right
  end
end
