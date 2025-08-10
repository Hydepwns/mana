defmodule Blockchain.Application do
  @moduledoc false

  use Application
  require Logger
  alias EVM.Debugger

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    _ =
      if breakpoint_address_hex = System.get_env("BREAKPOINT") do
        case Base.decode16(breakpoint_address_hex, case: :mixed) do
          {:ok, breakpoint_address} ->
            Debugger.enable()
            id = Debugger.break_on(address: breakpoint_address)

            :ok =
              Logger.warning(
                "Debugger has been enabled. Set breakpoint ##{id} on contract address 0x#{breakpoint_address_hex}."
              )

          :error ->
            _ = Logger.error("Invalid breakpoint address: #{breakpoint_address_hex}")
        end
      end

    # Get monitoring configuration from application environment
    monitoring_config = Application.get_env(:blockchain, :monitoring, [])

    # Get compliance configuration
    compliance_config = Application.get_env(:blockchain, :compliance, %{enabled: false})

    # Define workers and child supervisors to be supervised
    children = [
      # Start the transaction pool
      {Blockchain.TransactionPool, []},

      # Start monitoring and observability stack
      {Blockchain.Monitoring.MonitoringSupervisor, monitoring_config},

      # Start compliance system (if enabled)
      {Blockchain.Compliance.Supervisor, []}

      # Starts a worker by calling: Blockchain.Worker.start_link(arg1, arg2, arg3)
      # worker(Blockchain.Worker, [arg1, arg2, arg3]),
    ]

    # Log compliance status
    if compliance_config.enabled do
      Logger.info(
        "Compliance system enabled with standards: #{inspect(compliance_config.enabled_standards || [:sox, :pci_dss, :fips_140_2])}"
      )
    else
      Logger.info("Compliance system disabled")
    end

    opts = [strategy: :one_for_one, name: Blockchain.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
