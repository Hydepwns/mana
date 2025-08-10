defmodule Blockchain.Monitoring.PrometheusExporterTest do
  @moduledoc """
  Tests for the Prometheus metrics exporter.
  """

  use ExUnit.Case, async: false
  alias Blockchain.Monitoring.PrometheusExporter

  describe "PrometheusExporter" do
    setup do
      # Start telemetry application if not already started
      case Application.ensure_started(:telemetry) do
        :ok -> :ok
        {:error, {:already_started, :telemetry}} -> :ok
      end

      # Start the exporter for testing
      {:ok, _pid} = PrometheusExporter.start_link(enabled: true, collection_interval: 100)
      # Allow startup
      Process.sleep(50)

      on_exit(fn ->
        # Clean up
        if Process.whereis(PrometheusExporter), do: GenServer.stop(PrometheusExporter)
      end)

      :ok
    end

    test "starts successfully and is responsive" do
      assert is_pid(Process.whereis(PrometheusExporter))
    end

    test "exports metrics in Prometheus format" do
      # Record some test metrics
      PrometheusExporter.record_block_processed(12345, 150.0)
      PrometheusExporter.update_transaction_pool_size(42)
      PrometheusExporter.update_peer_count(8)

      # Get metrics output
      metrics_output = PrometheusExporter.get_metrics()

      assert is_binary(metrics_output)
      assert String.contains?(metrics_output, "mana_blockchain_height")
      assert String.contains?(metrics_output, "mana_transaction_pool_size")
      assert String.contains?(metrics_output, "mana_p2p_peers_connected")
      assert String.contains?(metrics_output, "# TYPE")
      assert String.contains?(metrics_output, "# HELP")
    end

    test "increments counters correctly" do
      initial_metrics = PrometheusExporter.get_metrics()

      # Record some operations
      PrometheusExporter.record_p2p_message("eth_getBlockByNumber", "outbound")
      PrometheusExporter.record_p2p_message("eth_getBlockByNumber", "inbound")
      PrometheusExporter.record_storage_operation("put", 25.0)

      final_metrics = PrometheusExporter.get_metrics()

      # Should contain the new metrics
      assert String.contains?(final_metrics, "mana_p2p_messages_total")
      assert String.contains?(final_metrics, "mana_storage_operations_total")
    end

    test "updates gauges correctly" do
      # Set some gauge values
      PrometheusExporter.update_peer_count(5)
      PrometheusExporter.update_transaction_pool_size(100)
      PrometheusExporter.update_sync_progress(0.75)

      metrics_output = PrometheusExporter.get_metrics()

      assert String.contains?(metrics_output, "mana_p2p_peers_connected 5")
      assert String.contains?(metrics_output, "mana_transaction_pool_size 100")
      assert String.contains?(metrics_output, "mana_sync_progress_ratio 0.75")
    end

    test "records histograms correctly" do
      # Record some execution times
      PrometheusExporter.record_evm_execution(125.5, 85000)
      PrometheusExporter.record_block_processed(54321, 200.0)

      metrics_output = PrometheusExporter.get_metrics()

      # Should contain histogram metrics (sum and count)
      assert String.contains?(metrics_output, "mana_evm_execution_seconds")
      assert String.contains?(metrics_output, "mana_block_processing_seconds")
    end

    test "collects system metrics automatically" do
      # Trigger system metrics collection
      PrometheusExporter.update_system_metrics()
      Process.sleep(10)

      metrics_output = PrometheusExporter.get_metrics()

      # Should contain system metrics
      assert String.contains?(metrics_output, "mana_memory_usage_bytes")
      assert String.contains?(metrics_output, "mana_erlang_processes")
      assert String.contains?(metrics_output, "mana_erlang_schedulers")
    end

    test "handles telemetry events" do
      # Emit some telemetry events
      :telemetry.execute([:mana, :block, :processed], %{duration: 150_000}, %{block_number: 12345})

      :telemetry.execute([:mana, :transaction, :processed], %{duration: 50_000}, %{
        gas_used: 21000
      })

      # Allow event processing
      Process.sleep(10)

      metrics_output = PrometheusExporter.get_metrics()

      # Should contain metrics from telemetry events
      assert String.contains?(metrics_output, "mana_blockchain_height")
      assert String.contains?(metrics_output, "mana_blocks_processed_total")
    end

    test "can be disabled via configuration" do
      # Stop the current exporter and start a disabled one
      GenServer.stop(PrometheusExporter)

      {:ok, _pid} = PrometheusExporter.start_link(enabled: false)

      metrics_output = PrometheusExporter.get_metrics()
      assert String.contains?(metrics_output, "# Prometheus metrics disabled")
    end

    test "formats labels correctly" do
      PrometheusExporter.record_p2p_message("eth_getBlockByNumber", "outbound")
      PrometheusExporter.record_storage_operation("get", 15.0)

      metrics_output = PrometheusExporter.get_metrics()

      # Should contain properly formatted labels
      assert String.contains?(metrics_output, ~s{message_type="eth_getBlockByNumber"})
      assert String.contains?(metrics_output, ~s{direction="outbound"})
      assert String.contains?(metrics_output, ~s{operation="get"})
    end
  end
end
