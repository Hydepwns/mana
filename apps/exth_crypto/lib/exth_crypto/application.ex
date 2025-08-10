defmodule ExthCrypto.Application do
  @moduledoc """
  Application module for ExthCrypto.

  This application starts the HSM supervisor if HSM is enabled in configuration.
  """

  use Application
  require Logger

  alias ExthCrypto.HSM.Supervisor, as: HSMSupervisor

  def start(_type, _args) do
    children = build_children()

    opts = [strategy: :one_for_one, name: ExthCrypto.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("ExthCrypto application started")

        if hsm_enabled?() do
          Logger.info("HSM integration is enabled")
        end

        {:ok, pid}

      error ->
        Logger.error("Failed to start ExthCrypto application: #{inspect(error)}")
        error
    end
  end

  defp build_children() do
    children = []

    # Add HSM supervisor if HSM is enabled
    children =
      if hsm_enabled?() do
        Logger.info("HSM enabled - starting HSM supervisor")
        [{HSMSupervisor, []} | children]
      else
        Logger.info("HSM disabled - skipping HSM supervisor")
        children
      end

    children
  end

  defp hsm_enabled?() do
    case Application.get_env(:exth_crypto, :hsm, %{}) do
      %{enabled: true} -> true
      config when is_map(config) -> Map.get(config, :enabled, false)
      _ -> false
    end
  end
end
