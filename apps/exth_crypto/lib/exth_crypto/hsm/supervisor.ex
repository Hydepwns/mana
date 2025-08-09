defmodule ExthCrypto.HSM.Supervisor do
  @moduledoc """
  Supervisor for all HSM-related processes.
  
  This supervisor coordinates the lifecycle of all HSM components:
  - Configuration Manager
  - PKCS#11 Interface
  - Key Manager
  - Signing Service
  - Monitor
  
  It handles startup order, dependencies, and graceful shutdown.
  """

  use Supervisor
  require Logger

  alias ExthCrypto.HSM.{ConfigManager, PKCS11Interface, KeyManager, SigningService, Monitor}

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      # Configuration manager starts first
      {ConfigManager, []},
      
      # PKCS#11 interface depends on configuration
      {PKCS11Interface, {ConfigManager, :get_component_config, [:pkcs11]}},
      
      # Key manager depends on PKCS#11 interface
      {KeyManager, {ConfigManager, :get_component_config, [:key_manager]}},
      
      # Signing service depends on key manager
      {SigningService, {ConfigManager, :get_component_config, [:signing_service]}},
      
      # Monitor starts last and monitors all other components
      {Monitor, []}
    ]

    # Use :rest_for_one strategy so that if PKCS#11 fails, all dependent services restart
    opts = [strategy: :rest_for_one, name: __MODULE__]
    
    Logger.info("Starting HSM Supervisor")
    Supervisor.init(children, opts)
  end

  @doc """
  Get the current status of all HSM processes.
  """
  def status() do
    children = Supervisor.which_children(__MODULE__)
    
    status_map = Enum.into(children, %{}, fn {name, pid, type, modules} ->
      process_status = if is_pid(pid) and Process.alive?(pid) do
        :running
      else
        :not_running
      end
      
      {name, %{
        pid: pid,
        type: type,
        modules: modules,
        status: process_status
      }}
    end)
    
    overall_status = if Enum.all?(status_map, fn {_name, info} -> info.status == :running end) do
      :healthy
    else
      :degraded
    end
    
    %{
      overall_status: overall_status,
      processes: status_map,
      started_at: get_supervisor_start_time()
    }
  end

  @doc """
  Gracefully restart a specific HSM component.
  """
  def restart_component(component) do
    case Supervisor.restart_child(__MODULE__, component) do
      {:ok, _pid} -> 
        Logger.info("HSM component #{component} restarted successfully")
        :ok
      
      {:ok, _pid, _info} -> 
        Logger.info("HSM component #{component} restarted successfully")
        :ok
      
      {:error, reason} -> 
        Logger.error("Failed to restart HSM component #{component}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get configuration for HSM components to determine if they should start.
  """
  def should_start_hsm?() do
    # Check if HSM is enabled in configuration
    case Application.get_env(:exth_crypto, :hsm, %{}) do
      %{enabled: true} -> true
      config when is_map(config) -> Map.get(config, :enabled, false)
      _ -> false
    end
  end

  defp get_supervisor_start_time() do
    # This is a simplified implementation - in production you'd track this
    DateTime.utc_now()
  end
end