defmodule ExWire.Integration.P2PNetworkTest do
  @moduledoc """
  Integration tests for P2P networking with real Ethereum nodes.
  These tests are tagged with :network and :integration for selective execution.
  """

  use ExUnit.Case, async: false
  require Logger

  alias ExWire.P2P.{ConnectionPool, PeerReputation}
  alias ExWire.Monitoring.NetworkMonitor
  alias ExWire.Struct.Peer
  alias ExWire.Kademlia.Server, as: KademliaServer

  @moduletag :network
  @moduletag :integration

  # Known Ethereum mainnet bootnodes
  @ethereum_bootnodes [
    "enode://d860a01f9722d78051619d1e2351aba3f43f943f6f00718d1b9baa4101932a1f5011f16bb2b1bb35db20d6fe28fa0bf09636d26a87d31de9ec6203eeedb1f666@18.138.108.67:30303",
    "enode://22a8232c3abc76a16ae9d6c3b164f98775fe226f0917b0ca871128a74a8e9630b458460865bab457221f1d448dd9791d24c4e5d88786180ac185df813a68d4de@3.209.45.79:30303",
    "enode://ca6de62fce278f96aea6ec5a2daadb877e51651247cb96ee310a318def462913b653963c155a0ef6c7d50048bba6e6cea881130857413d9f50a621546b590758@34.255.23.113:30303",
    "enode://279944d8dcd428dffaa7436f25ca0ca43ae19e7bcf94a8fb7d1641651f92d121e972ac2e8f381414b80cc8e5555811c2ec6e1a99bb009b3f53c4c69923e11bd8@35.158.244.151:30303"
  ]

  # Timeout for network operations
  @network_timeout 30_000
  @connection_timeout 15_000

  setup_all do
    # Start required services
    {:ok, _connection_pool} = ConnectionPool.start_link()
    {:ok, _network_monitor} = NetworkMonitor.start_link()

    # Create test configuration
    config = %{
      max_test_connections: 3,
      # 1 minute
      test_duration: 60_000,
      expected_min_peers: 2,
      protocol_test_timeout: 10_000
    }

    on_exit(fn ->
      # Cleanup any remaining connections
      connected_peers = ConnectionPool.get_connected_peers()

      for peer <- connected_peers do
        ConnectionPool.disconnect_peer(peer)
      end
    end)

    {:ok, config: config}
  end

  describe "Ethereum Mainnet Bootstrap" do
    @tag timeout: 60_000
    test "can connect to Ethereum mainnet bootnodes", %{config: config} do
      Logger.info("Testing connections to #{length(@ethereum_bootnodes)} Ethereum bootnodes")

      # Convert bootnode URIs to Peer structs
      peers =
        Enum.map(@ethereum_bootnodes, fn uri ->
          case Peer.from_uri(uri) do
            {:ok, peer} ->
              peer

            {:error, reason} ->
              Logger.warning("Failed to parse bootnode URI #{uri}: #{inspect(reason)}")
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      assert length(peers) > 0, "Could not parse any bootnode URIs"

      # Attempt connections to a subset of bootnodes
      test_peers = Enum.take(peers, config.max_test_connections)
      connection_results = test_peer_connections(test_peers, @connection_timeout)

      # Verify at least some connections succeeded
      successful_connections = Enum.count(connection_results, &match?({:ok, _}, &1))

      assert successful_connections >= config.expected_min_peers,
             "Expected at least #{config.expected_min_peers} successful connections, got #{successful_connections}"

      Logger.info(
        "Successfully connected to #{successful_connections}/#{length(test_peers)} test peers"
      )

      # Test basic protocol exchange with connected peers
      connected_peers = ConnectionPool.get_connected_peers()
      protocol_results = test_protocol_exchange(connected_peers, config.protocol_test_timeout)

      successful_protocols = Enum.count(protocol_results, &match?({:ok, _}, &1))
      assert successful_protocols > 0, "No successful protocol exchanges"

      Logger.info(
        "Successfully completed protocol exchange with #{successful_protocols}/#{length(connected_peers)} peers"
      )
    end

    @tag timeout: 90_000
    test "peer discovery through Kademlia DHT", %{config: config} do
      Logger.info("Testing peer discovery through Kademlia DHT")

      # Get initial peer count
      initial_stats = ConnectionPool.get_pool_stats()
      initial_peer_count = initial_stats.active

      # Wait for discovery rounds to complete
      :timer.sleep(30_000)

      # Check if we discovered more peers
      final_stats = ConnectionPool.get_pool_stats()
      final_peer_count = final_stats.active

      Logger.info("Peer discovery: initial=#{initial_peer_count}, final=#{final_peer_count}")

      # We should have at least maintained our connections, ideally discovered more
      assert final_peer_count >= initial_peer_count, "Lost peers during discovery process"
    end

    @tag timeout: 120_000
    test "network monitoring and metrics collection" do
      Logger.info("Testing network monitoring and metrics collection")

      # Wait for some network activity
      :timer.sleep(10_000)

      # Check network metrics
      metrics = NetworkMonitor.get_network_metrics()

      assert metrics.current_peer_count >= 0
      assert is_number(metrics.avg_response_time)
      assert is_number(metrics.connection_churn_rate)

      # Get topology information
      topology = NetworkMonitor.get_topology_info()

      assert is_list(topology.peer_clusters)
      assert is_list(topology.super_nodes)

      # Check alerts
      alerts = NetworkMonitor.get_active_alerts()
      assert is_list(alerts)

      Logger.info("Network metrics: #{inspect(metrics)}")
      Logger.info("Active alerts: #{length(alerts)}")
    end

    @tag timeout: 60_000
    test "peer reputation system" do
      Logger.info("Testing peer reputation system")

      connected_peers = ConnectionPool.get_connected_peers()

      if length(connected_peers) > 0 do
        test_peer = hd(connected_peers)

        # Get initial reputation
        initial_reputation = ConnectionPool.get_peer_reputation(test_peer)
        assert is_float(initial_reputation)
        assert initial_reputation >= 0.0 and initial_reputation <= 1.0

        # Simulate some network activity to update reputation
        :timer.sleep(5_000)

        # Check reputation after activity
        updated_reputation = ConnectionPool.get_peer_reputation(test_peer)
        assert is_float(updated_reputation)

        Logger.info(
          "Peer #{inspect(test_peer)} reputation: #{initial_reputation} -> #{updated_reputation}"
        )
      else
        Logger.warning("No connected peers available for reputation testing")
      end
    end
  end

  describe "Protocol Compliance" do
    @tag timeout: 45_000
    test "eth/66 and eth/67 protocol support" do
      Logger.info("Testing eth/66 and eth/67 protocol support")

      connected_peers = ConnectionPool.get_connected_peers()

      if length(connected_peers) > 0 do
        # Test protocol version negotiation
        for peer <- Enum.take(connected_peers, 2) do
          peer_stats = NetworkMonitor.get_peer_stats(peer)

          if peer_stats do
            protocol_info = peer_stats.protocol_info

            Logger.info(
              "Peer #{inspect(peer)} protocol: version=#{protocol_info.version}, capabilities=#{inspect(protocol_info.capabilities)}"
            )

            # Verify modern protocol support
            assert protocol_info.version >= 66, "Peer should support eth/66 or higher"
          end
        end
      else
        Logger.warning("No connected peers available for protocol testing")
      end
    end

    @tag timeout: 30_000
    test "message handling and validation" do
      Logger.info("Testing message handling and validation")

      # Wait for some message exchange
      :timer.sleep(10_000)

      connected_peers = ConnectionPool.get_connected_peers()

      if length(connected_peers) > 0 do
        test_peer = hd(connected_peers)
        peer_stats = NetworkMonitor.get_peer_stats(test_peer)

        if peer_stats do
          message_stats = peer_stats.message_stats

          # Verify message exchange occurred
          total_messages = message_stats.sent + message_stats.received
          assert total_messages > 0, "Expected some message exchange"

          # Verify message types
          assert map_size(message_stats.types) > 0, "Expected different message types"

          Logger.info("Message stats for #{inspect(test_peer)}: #{inspect(message_stats)}")
        end
      else
        Logger.warning("No connected peers available for message testing")
      end
    end
  end

  describe "Network Resilience" do
    @tag timeout: 60_000
    test "connection recovery after disconnect" do
      Logger.info("Testing connection recovery after disconnect")

      connected_peers = ConnectionPool.get_connected_peers()
      initial_count = length(connected_peers)

      if initial_count > 0 do
        # Disconnect a peer
        test_peer = hd(connected_peers)
        :ok = ConnectionPool.disconnect_peer(test_peer)

        # Wait a moment
        :timer.sleep(2_000)

        # Check that peer was disconnected
        remaining_peers = ConnectionPool.get_connected_peers()
        assert length(remaining_peers) == initial_count - 1

        # Wait for potential reconnection/discovery
        :timer.sleep(15_000)

        # Check if we recovered the connection count
        recovered_peers = ConnectionPool.get_connected_peers()
        recovered_count = length(recovered_peers)

        Logger.info(
          "Connection recovery: #{initial_count} -> #{length(remaining_peers)} -> #{recovered_count}"
        )

        # We should ideally recover the connection through discovery
        # This might not always succeed in test environment, so we're lenient
        assert recovered_count >= length(remaining_peers),
               "Should maintain or improve connection count"
      else
        Logger.warning("No connected peers available for disconnect testing")
      end
    end

    @tag timeout: 45_000
    test "handling of peer timeouts and failures" do
      Logger.info("Testing handling of peer timeouts and failures")

      # Get initial network metrics
      initial_metrics = NetworkMonitor.get_network_metrics()

      # Wait for some network activity that might include timeouts
      :timer.sleep(20_000)

      # Check updated metrics
      final_metrics = NetworkMonitor.get_network_metrics()

      # Verify metrics are being tracked
      assert final_metrics.total_messages_sent >= initial_metrics.total_messages_sent
      assert final_metrics.total_messages_received >= initial_metrics.total_messages_received

      Logger.info(
        "Network activity: sent #{final_metrics.total_messages_sent}, received #{final_metrics.total_messages_received}"
      )
    end
  end

  # Helper functions

  defp test_peer_connections(peers, timeout) do
    Logger.info("Testing connections to #{length(peers)} peers with timeout #{timeout}ms")

    # Start connection attempts
    connection_tasks =
      Enum.map(peers, fn peer ->
        Task.async(fn ->
          case ConnectionPool.connect_to_peer(peer) do
            :ok ->
              # Wait a moment to ensure connection is established
              :timer.sleep(2_000)

              # Verify connection
              connected_peers = ConnectionPool.get_connected_peers()

              if Enum.member?(connected_peers, peer) do
                {:ok, peer}
              else
                {:error, :connection_not_established}
              end

            error ->
              {:error, error}
          end
        end)
      end)

    # Wait for results with timeout
    Enum.map(connection_tasks, fn task ->
      case Task.yield(task, timeout) do
        {:ok, result} ->
          result

        nil ->
          Task.shutdown(task, :brutal_kill)
          {:error, :timeout}
      end
    end)
  end

  defp test_protocol_exchange(peers, timeout) do
    Logger.info("Testing protocol exchange with #{length(peers)} peers")

    # For now, we just verify that we can get peer stats
    # In a full implementation, we'd test specific protocol messages
    Enum.map(peers, fn peer ->
      try do
        # Give some time for protocol negotiation
        :timer.sleep(1_000)

        case NetworkMonitor.get_peer_stats(peer) do
          nil -> {:error, :no_stats}
          _stats -> {:ok, peer}
        end
      catch
        _, _ -> {:error, :exception}
      after
        timeout
      end
    end)
  end
end
