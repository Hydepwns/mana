defmodule Blockchain.Monitoring.StructuredLoggerTest do
  @moduledoc """
  Tests for the structured logging system.
  """

  use ExUnit.Case, async: false
  alias Blockchain.Monitoring.StructuredLogger
  import ExUnit.CaptureLog

  describe "StructuredLogger initialization" do
    test "initializes with default configuration" do
      assert :ok = StructuredLogger.init()
      config = Process.get(:structured_logger_config)
      
      assert config.format == :human
      assert config.min_level == :info
      assert config.sampling_rate == 1.0
      assert is_binary(config.node_id)
      assert is_binary(config.version)
    end

    test "initializes with custom configuration" do
      opts = [
        format: :json,
        min_level: :debug,
        sampling_rate: 0.5,
        node_id: "test-node-123",
        version: "1.0.0"
      ]
      
      assert :ok = StructuredLogger.init(opts)
      config = Process.get(:structured_logger_config)
      
      assert config.format == :json
      assert config.min_level == :debug
      assert config.sampling_rate == 0.5
      assert config.node_id == "test-node-123"
      assert config.version == "1.0.0"
    end
  end

  describe "basic logging functions" do
    setup do
      StructuredLogger.init(format: :human, min_level: :debug)
      :ok
    end

    test "logs at different levels" do
      log_output = capture_log(fn ->
        StructuredLogger.debug("test", "Debug message")
        StructuredLogger.info("test", "Info message")  
        StructuredLogger.warn("test", "Warning message")
        StructuredLogger.error("test", "Error message")
      end)

      assert String.contains?(log_output, "Debug message")
      assert String.contains?(log_output, "Info message")
      assert String.contains?(log_output, "Warning message")
      assert String.contains?(log_output, "Error message")
    end

    test "respects minimum log level" do
      StructuredLogger.init(format: :human, min_level: :warn)
      
      log_output = capture_log(fn ->
        StructuredLogger.debug("test", "Should not appear")
        StructuredLogger.info("test", "Should not appear")
        StructuredLogger.warn("test", "Should appear")
        StructuredLogger.error("test", "Should appear")
      end)

      refute String.contains?(log_output, "Should not appear")
      assert String.contains?(log_output, "Should appear")
    end

    test "includes component in log output" do
      log_output = capture_log(fn ->
        StructuredLogger.info("blockchain", "Block processed")
      end)

      assert String.contains?(log_output, "[blockchain]")
      assert String.contains?(log_output, "Block processed")
    end

    test "includes context in log output" do
      log_output = capture_log(fn ->
        StructuredLogger.info("test", "Message with context", %{
          user_id: "123",
          session_id: "abc-456"
        })
      end)

      assert String.contains?(log_output, "user_id=")
      assert String.contains?(log_output, "session_id=")
    end
  end

  describe "specialized logging functions" do
    setup do
      StructuredLogger.init(format: :human, min_level: :debug)
      :ok
    end

    test "logs performance measurements" do
      log_output = capture_log(fn ->
        StructuredLogger.log_performance("storage", "get_operation", 125.5)
      end)

      assert String.contains?(log_output, "Performance measurement")
      assert String.contains?(log_output, "get_operation")
      assert String.contains?(log_output, "duration_ms=125.5")
    end

    test "logs errors with stack traces" do
      try do
        raise ArgumentError, "Test error"
      rescue
        error ->
          log_output = capture_log(fn ->
            StructuredLogger.log_error("test", "Error occurred", error, __STACKTRACE__)
          end)

          assert String.contains?(log_output, "Error occurred")
          assert String.contains?(log_output, "error_type=ArgumentError")
          assert String.contains?(log_output, "error_message=\"Test error\"")
      end
    end

    test "logs requests and responses" do
      request_log = capture_log(fn ->
        StructuredLogger.log_request("rpc", "eth_getBalance", "req-123", %{
          address: "0x123",
          block: "latest"
        })
      end)

      assert String.contains?(request_log, "Request received")
      assert String.contains?(request_log, "request_id=\"req-123\"")
      assert String.contains?(request_log, "request_type=\"eth_getBalance\"")

      response_log = capture_log(fn ->
        StructuredLogger.log_response("rpc", "eth_getBalance", "req-123", %{
          balance: "1000000000000000000"
        }, 45.2)
      end)

      assert String.contains?(response_log, "Response sent")
      assert String.contains?(response_log, "duration_ms=45.2")
    end

    test "logs blockchain events" do
      log_output = capture_log(fn ->
        StructuredLogger.log_blockchain_event("block_processed", "Block #12345 processed", %{
          block_number: 12345,
          transaction_count: 42,
          gas_used: 8000000
        })
      end)

      assert String.contains?(log_output, "Block #12345 processed")
      assert String.contains?(log_output, "event_type=\"block_processed\"")
      assert String.contains?(log_output, "blockchain=true")
    end

    test "logs P2P events" do
      log_output = capture_log(fn ->
        StructuredLogger.log_p2p_event("message_received", "Received eth_getBlockByNumber", %{
          message_type: "eth_getBlockByNumber",
          direction: "inbound",
          peer_id: "peer-123"
        })
      end)

      assert String.contains?(log_output, "Received eth_getBlockByNumber")
      assert String.contains?(log_output, "p2p=true")
      assert String.contains?(log_output, "message_type=\"eth_getBlockByNumber\"")
    end

    test "logs security events" do
      log_output = capture_log(fn ->
        StructuredLogger.log_security_event("authentication_failure", "Invalid API key", %{
          ip_address: "192.168.1.100",
          user_agent: "curl/7.68.0"
        })
      end)

      assert String.contains?(log_output, "SECURITY: Invalid API key")
      assert String.contains?(log_output, "security=true")
      assert String.contains?(log_output, "severity=\"high\"")
    end
  end

  describe "context management" do
    setup do
      StructuredLogger.init(format: :human, min_level: :debug)
      StructuredLogger.clear_context()
      :ok
    end

    test "sets and gets context" do
      assert StructuredLogger.get_context() == %{}
      
      StructuredLogger.set_context(%{request_id: "req-123"})
      assert StructuredLogger.get_context() == %{request_id: "req-123"}
      
      StructuredLogger.set_context(%{user_id: "user-456"})
      assert StructuredLogger.get_context() == %{request_id: "req-123", user_id: "user-456"}
    end

    test "uses context in log messages" do
      StructuredLogger.set_context(%{request_id: "req-123", session_id: "sess-456"})
      
      log_output = capture_log(fn ->
        StructuredLogger.info("test", "Test message")
      end)

      assert String.contains?(log_output, "request_id=\"req-123\"")
      assert String.contains?(log_output, "session_id=\"sess-456\"")
    end

    test "clears context" do
      StructuredLogger.set_context(%{request_id: "req-123"})
      assert StructuredLogger.get_context() != %{}
      
      StructuredLogger.clear_context()
      assert StructuredLogger.get_context() == %{}
    end
  end

  describe "JSON format logging" do
    setup do
      StructuredLogger.init(format: :json, min_level: :debug)
      :ok
    end

    test "outputs valid JSON" do
      log_output = capture_log(fn ->
        StructuredLogger.info("test", "JSON test message", %{key: "value"})
      end)

      # Extract JSON from log output (remove log level prefix)
      json_line = log_output |> String.trim() |> String.split("\n") |> List.first()
      json_part = Regex.run(~r/\[info\]\s+(.+)$/, json_line) |> List.last()
      
      assert {:ok, parsed} = Jason.decode(json_part)
      assert parsed["message"] == "JSON test message"
      assert parsed["component"] == "test"
      assert parsed["level"] == "info"
      assert parsed["context"]["key"] == "value"
    end
  end

  describe "data sanitization" do
    setup do
      StructuredLogger.init(format: :human, min_level: :debug)
      :ok
    end

    test "sanitizes sensitive data in requests" do
      log_output = capture_log(fn ->
        StructuredLogger.log_request("rpc", "eth_sendTransaction", "req-123", %{
          password: "secret123",
          private_key: "0xabcdef...",
          from: "0x123"
        })
      end)

      assert String.contains?(log_output, "[REDACTED]")
      refute String.contains?(log_output, "secret123")
      refute String.contains?(log_output, "0xabcdef...")
      assert String.contains?(log_output, "0x123")  # Non-sensitive data should remain
    end

    test "limits large data structures" do
      large_data = String.duplicate("x", 2000)
      
      log_output = capture_log(fn ->
        StructuredLogger.log_request("test", "large_request", "req-123", %{
          data: large_data
        })
      end)

      assert String.contains?(log_output, "[TRUNCATED]")
    end
  end

  describe "component validation" do
    test "provides valid component identifiers" do
      components = StructuredLogger.get_components()
      
      assert is_map(components)
      assert components.blockchain == "blockchain"
      assert components.p2p == "p2p"
      assert components.rpc == "rpc"
    end

    test "validates component identifiers" do
      assert StructuredLogger.valid_component?("blockchain")
      assert StructuredLogger.valid_component?("p2p")
      refute StructuredLogger.valid_component?("invalid_component")
    end
  end

  describe "sampling" do
    test "respects sampling rate" do
      # Set very low sampling rate
      StructuredLogger.init(format: :human, min_level: :debug, sampling_rate: 0.0)
      
      log_output = capture_log(fn ->
        # Try to log multiple messages - none should appear due to 0% sampling
        for _ <- 1..10 do
          StructuredLogger.info("test", "Sampled message")
        end
      end)

      # With 0% sampling, no messages should appear
      refute String.contains?(log_output, "Sampled message")
    end
  end
end