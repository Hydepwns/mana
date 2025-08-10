defmodule ExWire.Sync.SnapshotGeneratorTest do
  @moduledoc """
  Comprehensive test suite for the SnapshotGenerator system.
  Tests snapshot generation, incremental updates, compression,
  and integration with AntidoteDB.
  """

  use ExUnit.Case, async: false
  alias ExWire.Sync.SnapshotGenerator
  alias MerklePatriciaTree.{Trie, TrieStorage}
  alias MerklePatriciaTree.DB.ETS

  @moduletag :integration

  setup do
    # Create test database and trie
    db = ETS.new()
    trie = TrieStorage.new(db)

    # Start SnapshotGenerator with test configuration
    opts = [
      trie: trie,
      serving_enabled: true,
      # Small chunks for testing
      max_chunk_size: 1024,
      # Fast compression for tests
      compression_level: 1
    ]

    {:ok, generator} = SnapshotGenerator.start_link(opts)

    on_exit(fn ->
      if Process.alive?(generator) do
        GenServer.stop(generator, :normal, 1000)
      end
    end)

    {:ok, generator: generator, trie: trie, db: db}
  end

  describe "Snapshot Generation" do
    test "generates basic snapshot for empty state", %{generator: generator} do
      block_number = 100

      # Generate snapshot
      assert {:ok, :generating} = SnapshotGenerator.generate_snapshot(block_number)

      # Wait for generation to complete
      receive do
        {:snapshot_generated, {:ok, result}} ->
          assert result.manifest.block_number == block_number
          assert result.manifest.version == 2
          assert is_list(result.state_chunks)
          assert is_list(result.block_chunks)
          assert result.total_size_bytes > 0
          assert result.compression_ratio > 0

        {:snapshot_generated, {:error, reason}} ->
          flunk("Snapshot generation failed: #{inspect(reason)}")
      after
        10_000 -> flunk("Timeout waiting for snapshot generation")
      end
    end

    test "generates snapshot with compression", %{generator: generator} do
      block_number = 200

      # Generate snapshot with compression enabled
      assert {:ok, :generating} =
               SnapshotGenerator.generate_snapshot(block_number, compression: true)

      receive do
        {:snapshot_generated, {:ok, result}} ->
          # Compression ratio should be > 1 (data was compressed)
          assert result.compression_ratio >= 1.0
          assert result.generation_time_ms > 0

        {:snapshot_generated, {:error, reason}} ->
          flunk("Compressed snapshot generation failed: #{inspect(reason)}")
      after
        10_000 -> flunk("Timeout waiting for compressed snapshot generation")
      end
    end

    test "handles concurrent snapshot generation", %{generator: generator} do
      # Generate multiple snapshots concurrently
      tasks =
        for i <- 1..3 do
          Task.async(fn ->
            block_number = 300 + i
            {:ok, :generating} = SnapshotGenerator.generate_snapshot(block_number)

            receive do
              {:snapshot_generated, result} -> {block_number, result}
            after
              15_000 -> {:timeout, block_number}
            end
          end)
        end

      # Wait for all tasks to complete
      results = Task.await_many(tasks, 20_000)

      # Verify all snapshots were generated successfully
      Enum.each(results, fn
        {block_number, {:ok, result}} ->
          assert result.manifest.block_number == block_number

        {block_number, {:error, reason}} ->
          flunk("Snapshot #{block_number} failed: #{inspect(reason)}")

        {:timeout, block_number} ->
          flunk("Snapshot #{block_number} timed out")
      end)
    end
  end

  describe "Incremental Snapshots" do
    test "generates incremental snapshot between blocks", %{generator: generator} do
      from_block = 100
      to_block = 200

      # Generate incremental snapshot
      assert {:ok, :generating} = SnapshotGenerator.generate_incremental(from_block, to_block)

      receive do
        {:snapshot_generated, {:ok, result}} ->
          assert result.manifest.block_number == to_block
          # Incremental snapshots should have good compression
          assert result.compression_ratio >= 2.0
          # Should be relatively fast to generate
          assert result.generation_time_ms < 5000

        {:snapshot_generated, {:error, reason}} ->
          flunk("Incremental snapshot generation failed: #{inspect(reason)}")
      after
        10_000 -> flunk("Timeout waiting for incremental snapshot generation")
      end
    end
  end

  describe "Serving Information" do
    test "provides serving information", %{generator: generator} do
      # Initially no snapshots
      serving_info = SnapshotGenerator.get_serving_info()
      assert serving_info.serving_enabled == true
      assert serving_info.snapshots == []

      # Generate a snapshot
      assert {:ok, :generating} = SnapshotGenerator.generate_snapshot(150)

      receive do
        {:snapshot_generated, {:ok, _result}} ->
          # Check serving info after generation
          updated_info = SnapshotGenerator.get_serving_info()
          assert updated_info.serving_enabled == true
          assert length(updated_info.snapshots) == 1

          [snapshot_info] = updated_info.snapshots
          assert snapshot_info.block_number == 150
          assert snapshot_info.chunks_count > 0

        {:snapshot_generated, {:error, reason}} ->
          flunk("Snapshot generation failed: #{inspect(reason)}")
      after
        10_000 -> flunk("Timeout waiting for snapshot generation")
      end
    end

    test "gets latest manifest", %{generator: generator} do
      # Initially no manifest
      assert {:error, :no_snapshots} = SnapshotGenerator.get_latest_manifest()

      # Generate snapshot
      assert {:ok, :generating} = SnapshotGenerator.generate_snapshot(300)

      receive do
        {:snapshot_generated, {:ok, _result}} ->
          # Should now have a manifest
          assert {:ok, manifest} = SnapshotGenerator.get_latest_manifest()
          assert manifest.block_number == 300
          assert manifest.version == 2

        {:snapshot_generated, {:error, reason}} ->
          flunk("Snapshot generation failed: #{inspect(reason)}")
      after
        10_000 -> flunk("Timeout waiting for snapshot generation")
      end
    end
  end

  describe "Chunk Retrieval" do
    test "retrieves chunks by hash after generation", %{generator: generator} do
      # Generate snapshot first
      assert {:ok, :generating} = SnapshotGenerator.generate_snapshot(400)

      receive do
        {:snapshot_generated, {:ok, result}} ->
          # Try to retrieve chunks using their hashes
          state_hashes = result.manifest.state_hashes
          block_hashes = result.manifest.block_hashes

          # Test retrieving state chunks
          Enum.each(state_hashes, fn chunk_hash ->
            case SnapshotGenerator.get_chunk_by_hash(chunk_hash) do
              {:ok, chunk_data} ->
                assert is_binary(chunk_data)
                assert byte_size(chunk_data) > 0

              {:error, :not_found} ->
                flunk("State chunk not found: #{Base.encode16(chunk_hash, case: :lower)}")
            end
          end)

          # Test retrieving block chunks
          Enum.each(block_hashes, fn chunk_hash ->
            case SnapshotGenerator.get_chunk_by_hash(chunk_hash) do
              {:ok, chunk_data} ->
                assert is_binary(chunk_data)
                assert byte_size(chunk_data) > 0

              {:error, :not_found} ->
                flunk("Block chunk not found: #{Base.encode16(chunk_hash, case: :lower)}")
            end
          end)

        {:snapshot_generated, {:error, reason}} ->
          flunk("Snapshot generation failed: #{inspect(reason)}")
      after
        10_000 -> flunk("Timeout waiting for snapshot generation")
      end
    end

    test "returns error for non-existent chunks", %{generator: _generator} do
      fake_hash = :crypto.hash(:sha256, "non_existent_chunk")
      assert {:error, :not_found} = SnapshotGenerator.get_chunk_by_hash(fake_hash)
    end
  end

  describe "Statistics" do
    test "tracks generation statistics", %{generator: generator} do
      # Get initial stats
      initial_stats = SnapshotGenerator.get_stats()
      assert initial_stats.total_snapshots_generated == 0
      assert initial_stats.total_generation_time_ms == 0

      # Generate a snapshot
      assert {:ok, :generating} = SnapshotGenerator.generate_snapshot(500)

      receive do
        {:snapshot_generated, {:ok, _result}} ->
          # Check updated stats
          updated_stats = SnapshotGenerator.get_stats()
          assert updated_stats.total_snapshots_generated == 1
          assert updated_stats.total_generation_time_ms > 0
          assert updated_stats.total_bytes_generated > 0
          assert updated_stats.average_compression_ratio > 0
          assert updated_stats.last_generation != nil

        {:snapshot_generated, {:error, reason}} ->
          flunk("Snapshot generation failed: #{inspect(reason)}")
      after
        10_000 -> flunk("Timeout waiting for snapshot generation")
      end
    end
  end

  describe "Serving Control" do
    test "enables and disables serving", %{generator: _generator} do
      # Initially enabled
      info = SnapshotGenerator.get_serving_info()
      assert info.serving_enabled == true

      # Disable serving
      :ok = SnapshotGenerator.set_serving_enabled(false)

      # Wait a moment for the cast to be processed
      Process.sleep(100)

      # Check serving is disabled
      disabled_info = SnapshotGenerator.get_serving_info()
      assert disabled_info.serving_enabled == false

      # Re-enable serving
      :ok = SnapshotGenerator.set_serving_enabled(true)

      Process.sleep(100)

      # Check serving is enabled again
      enabled_info = SnapshotGenerator.get_serving_info()
      assert enabled_info.serving_enabled == true
    end
  end

  describe "Performance" do
    @tag :performance
    test "generates snapshots within reasonable time limits", %{generator: generator} do
      # Generate snapshot and measure time
      start_time = System.monotonic_time(:millisecond)

      assert {:ok, :generating} = SnapshotGenerator.generate_snapshot(600)

      receive do
        {:snapshot_generated, {:ok, result}} ->
          end_time = System.monotonic_time(:millisecond)
          total_time = end_time - start_time

          # Should complete within 5 seconds for test data
          assert total_time < 5000, "Snapshot generation took too long: #{total_time}ms"

          # Reported generation time should be reasonable
          assert result.generation_time_ms < total_time
          assert result.generation_time_ms > 0

        {:snapshot_generated, {:error, reason}} ->
          flunk("Snapshot generation failed: #{inspect(reason)}")
      after
        10_000 -> flunk("Timeout waiting for snapshot generation")
      end
    end

    @tag :performance
    test "maintains good compression ratios", %{generator: generator} do
      # Generate snapshot with compression
      assert {:ok, :generating} = SnapshotGenerator.generate_snapshot(700, compression: true)

      receive do
        {:snapshot_generated, {:ok, result}} ->
          # Should achieve some compression (ratio > 1.0)
          assert result.compression_ratio >= 1.0

          # For test data, should achieve at least modest compression
          assert result.compression_ratio >= 1.2,
                 "Poor compression ratio: #{result.compression_ratio}"

        {:snapshot_generated, {:error, reason}} ->
          flunk("Snapshot generation failed: #{inspect(reason)}")
      after
        10_000 -> flunk("Timeout waiting for snapshot generation")
      end
    end
  end

  describe "Error Handling" do
    test "handles invalid block numbers gracefully", %{generator: generator} do
      # Try to generate snapshot for a very high block number
      invalid_block = 999_999_999

      assert {:ok, :generating} = SnapshotGenerator.generate_snapshot(invalid_block)

      receive do
        {:snapshot_generated, {:ok, result}} ->
          # Should still generate something, even if empty
          assert result.manifest.block_number == invalid_block

        {:snapshot_generated, {:error, _reason}} ->
          # Error is also acceptable for invalid block numbers
          :ok
      after
        10_000 -> flunk("Timeout waiting for snapshot generation")
      end
    end
  end
end
