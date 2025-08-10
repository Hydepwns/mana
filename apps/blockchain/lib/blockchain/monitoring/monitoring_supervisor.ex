defmodule Blockchain.Monitoring.MonitoringSupervisor do
  @moduledoc """
  Supervisor for all monitoring and observability components.
  
  Manages:
  - PrometheusExporter (metrics collection)
  - MetricsEndpoint (HTTP metrics server)  
  - TelemetryIntegrator (instrumentation)
  """

  use Supervisor
  require Logger

  @name __MODULE__

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: @name)
  end

  @impl true
  def init(opts) do
    monitoring_enabled = Keyword.get(opts, :enabled, true)
    
    if monitoring_enabled do
      Logger.info("[MonitoringSupervisor] Starting monitoring and observability stack")
      
      # Get configuration
      prometheus_config = Keyword.get(opts, :prometheus, [])
      metrics_endpoint_config = Keyword.get(opts, :metrics_endpoint, [])
      telemetry_config = Keyword.get(opts, :telemetry, [])
      
      children = [
        # Start Prometheus metrics registry
        {Blockchain.Monitoring.PrometheusMetrics, []},
        
        # Start Prometheus metrics exporter
        {Blockchain.Monitoring.PrometheusExporter, prometheus_config},
        
        # Start HTTP metrics endpoint
        {Blockchain.Monitoring.MetricsEndpoint, metrics_endpoint_config}
      ]
      
      # Initialize Prometheus metrics
      Task.start(fn ->
        Process.sleep(500)  # Wait for registry setup
        Blockchain.Monitoring.PrometheusMetrics.setup()
      end)
      
      # Initialize telemetry integration
      Task.start(fn ->
        Process.sleep(1000)  # Wait for other components to start
        if Keyword.get(telemetry_config, :auto_instrument, true) do
          Blockchain.Monitoring.TelemetryIntegrator.auto_instrument()
        end
      end)
      
      opts = [strategy: :one_for_one, name: @name]
      Supervisor.init(children, opts)
    else
      Logger.info("[MonitoringSupervisor] Monitoring disabled by configuration")
      Supervisor.init([], strategy: :one_for_one, name: @name)
    end
  end

  @doc """
  Get the current status of all monitoring components.
  """
  @spec get_monitoring_status() :: map()
  def get_monitoring_status() do
    case Supervisor.which_children(@name) do
      [] ->
        %{enabled: false, components: []}
      
      children ->
        component_status = 
          children
          |> Enum.map(fn {id, pid, _type, _modules} ->
            status = if is_pid(pid) and Process.alive?(pid) do
              :running
            else
              :stopped
            end
            
            %{
              id: id,
              pid: pid,
              status: status
            }
          end)
        
        %{
          enabled: true,
          components: component_status,
          metrics_url: get_metrics_url(),
          health_url: get_health_url()
        }
    end
  end

  @doc """
  Get the metrics URL if the endpoint is running.
  """
  @spec get_metrics_url() :: String.t() | nil
  def get_metrics_url() do
    try do
      Blockchain.Monitoring.MetricsEndpoint.get_metrics_url()
    rescue
      _ -> nil
    end
  end

  @doc """
  Get the health check URL if the endpoint is running.
  """
  @spec get_health_url() :: String.t() | nil
  def get_health_url() do
    case get_metrics_url() do
      nil -> nil
      url -> String.replace(url, "/metrics", "/health")
    end
  end

  @doc """
  Emit test metrics to verify the monitoring stack is working.
  """
  @spec emit_test_metrics() :: :ok
  def emit_test_metrics() do
    Logger.info("[MonitoringSupervisor] Emitting test metrics")
    Blockchain.Monitoring.TelemetryIntegrator.emit_test_events()
    :ok
  end

  @doc """
  Get comprehensive monitoring information for debugging.
  """
  @spec get_debug_info() :: map()
  def get_debug_info() do
    %{
      supervisor_status: get_monitoring_status(),
      telemetry_handlers: Blockchain.Monitoring.TelemetryIntegrator.list_telemetry_handlers(),
      system_info: %{
        memory: :erlang.memory(),
        process_count: :erlang.system_info(:process_count),
        schedulers: :erlang.system_info(:schedulers),
        uptime: :erlang.statistics(:wall_clock) |> elem(0)
      }
    }
  end
end