defmodule MerklePatriciaTree.DB.BackupManager do
  @moduledoc """
  Manages automatic backups and snapshots for AntidoteDB.
  Provides scheduled backups, snapshot creation, and restoration capabilities.
  """

  use GenServer
  require Logger

  alias MerklePatriciaTree.DB.{AntidoteClient, AntidoteConnectionPool}

  @default_backup_interval_ms 3600_000  # 1 hour
  @default_backup_dir "/var/backups/antidote"
  @max_backups_to_keep 24  # Keep last 24 hourly backups
  @snapshot_format_version "1.0"

  # Client API

  @doc """
  Starts the BackupManager GenServer.
  
  ## Options
    - backup_interval_ms: Interval between automatic backups (default: 1 hour)
    - backup_dir: Directory to store backups (default: /var/backups/antidote)
    - enabled: Enable automatic backups (default: true)
    - max_backups: Maximum number of backups to retain (default: 24)
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Triggers an immediate backup.
  """
  def backup_now(description \\ "manual") do
    GenServer.call(__MODULE__, {:backup_now, description}, :infinity)
  end

  @doc """
  Creates a snapshot of the current state.
  """
  def create_snapshot(name, description \\ "") do
    GenServer.call(__MODULE__, {:create_snapshot, name, description}, :infinity)
  end

  @doc """
  Restores from a specific backup or snapshot.
  """
  def restore(backup_id) do
    GenServer.call(__MODULE__, {:restore, backup_id}, :infinity)
  end

  @doc """
  Lists available backups and snapshots.
  """
  def list_backups do
    GenServer.call(__MODULE__, :list_backups)
  end

  @doc """
  Gets backup statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    state = %{
      enabled: Keyword.get(opts, :enabled, true),
      backup_interval_ms: Keyword.get(opts, :backup_interval_ms, @default_backup_interval_ms),
      backup_dir: Keyword.get(opts, :backup_dir, @default_backup_dir),
      max_backups: Keyword.get(opts, :max_backups, @max_backups_to_keep),
      last_backup: nil,
      backup_count: 0,
      total_backup_size: 0,
      backup_history: [],
      stats: %{
        successful_backups: 0,
        failed_backups: 0,
        successful_restores: 0,
        failed_restores: 0,
        total_backup_time_ms: 0,
        total_restore_time_ms: 0
      }
    }

    # Ensure backup directory exists
    File.mkdir_p!(state.backup_dir)

    # Schedule first backup if enabled
    if state.enabled do
      schedule_next_backup(state.backup_interval_ms)
    end

    # Load existing backup metadata
    state = load_backup_metadata(state)

    {:ok, state}
  end

  @impl true
  def handle_call({:backup_now, description}, _from, state) do
    case perform_backup(state, description) do
      {:ok, backup_info, new_state} ->
        {:reply, {:ok, backup_info}, new_state}
      
      {:error, reason} = error ->
        new_state = update_stats(state, :backup_failed)
        Logger.error("Backup failed: #{inspect(reason)}")
        {:reply, error, new_state}
    end
  end

  @impl true
  def handle_call({:create_snapshot, name, description}, _from, state) do
    case create_snapshot_internal(state, name, description) do
      {:ok, snapshot_info, new_state} ->
        {:reply, {:ok, snapshot_info}, new_state}
      
      {:error, reason} = error ->
        Logger.error("Snapshot creation failed: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:restore, backup_id}, _from, state) do
    case perform_restore(state, backup_id) do
      {:ok, restore_info, new_state} ->
        {:reply, {:ok, restore_info}, new_state}
      
      {:error, reason} = error ->
        new_state = update_stats(state, :restore_failed)
        Logger.error("Restore failed: #{inspect(reason)}")
        {:reply, error, new_state}
    end
  end

  @impl true
  def handle_call(:list_backups, _from, state) do
    backups = list_available_backups(state)
    {:reply, backups, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = compile_stats(state)
    {:reply, stats, state}
  end

  @impl true
  def handle_info(:scheduled_backup, state) do
    # Perform automatic backup
    new_state = 
      case perform_backup(state, "scheduled") do
        {:ok, _backup_info, updated_state} ->
          Logger.info("Scheduled backup completed successfully")
          updated_state
        
        {:error, reason} ->
          Logger.error("Scheduled backup failed: #{inspect(reason)}")
          update_stats(state, :backup_failed)
      end

    # Schedule next backup
    if new_state.enabled do
      schedule_next_backup(new_state.backup_interval_ms)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup_old_backups, state) do
    new_state = cleanup_old_backups(state)
    schedule_cleanup()
    {:noreply, new_state}
  end

  # Private functions

  defp perform_backup(state, description) do
    start_time = System.monotonic_time(:millisecond)
    backup_id = generate_backup_id()
    backup_path = Path.join(state.backup_dir, backup_id)
    
    try do
      # Create backup directory
      File.mkdir_p!(backup_path)
      
      # Get AntidoteDB connection
      with {:ok, client} <- get_antidote_connection(),
           {:ok, data} <- export_antidote_data(client),
           :ok <- write_backup_data(backup_path, data),
           :ok <- write_backup_metadata(backup_path, description, data) do
        
        end_time = System.monotonic_time(:millisecond)
        duration_ms = end_time - start_time
        
        backup_info = %{
          id: backup_id,
          path: backup_path,
          description: description,
          timestamp: DateTime.utc_now(),
          size_bytes: calculate_backup_size(backup_path),
          duration_ms: duration_ms,
          status: :success
        }
        
        new_state = 
          state
          |> Map.put(:last_backup, backup_info)
          |> Map.update!(:backup_count, &(&1 + 1))
          |> Map.update!(:backup_history, &([backup_info | &1]))
          |> update_stats(:backup_success, duration_ms)
        
        {:ok, backup_info, new_state}
      else
        error ->
          # Clean up partial backup
          File.rm_rf(backup_path)
          error
      end
    rescue
      e ->
        File.rm_rf(backup_path)
        {:error, Exception.message(e)}
    end
  end

  defp create_snapshot_internal(state, name, description) do
    snapshot_id = "snapshot_#{name}_#{System.os_time(:second)}"
    snapshot_path = Path.join([state.backup_dir, "snapshots", snapshot_id])
    
    try do
      File.mkdir_p!(snapshot_path)
      
      with {:ok, client} <- get_antidote_connection(),
           {:ok, snapshot_data} <- create_antidote_snapshot(client),
           :ok <- write_snapshot_data(snapshot_path, snapshot_data),
           :ok <- write_snapshot_metadata(snapshot_path, name, description) do
        
        snapshot_info = %{
          id: snapshot_id,
          name: name,
          path: snapshot_path,
          description: description,
          timestamp: DateTime.utc_now(),
          size_bytes: calculate_backup_size(snapshot_path)
        }
        
        new_state = Map.update!(state, :backup_history, &([snapshot_info | &1]))
        
        {:ok, snapshot_info, new_state}
      else
        error ->
          File.rm_rf(snapshot_path)
          error
      end
    rescue
      e ->
        File.rm_rf(snapshot_path)
        {:error, Exception.message(e)}
    end
  end

  defp perform_restore(state, backup_id) do
    start_time = System.monotonic_time(:millisecond)
    backup_path = find_backup_path(state, backup_id)
    
    case backup_path do
      nil ->
        {:error, :backup_not_found}
      
      path ->
        with {:ok, metadata} <- read_backup_metadata(path),
             {:ok, data} <- read_backup_data(path),
             {:ok, client} <- get_antidote_connection(),
             :ok <- import_antidote_data(client, data) do
          
          end_time = System.monotonic_time(:millisecond)
          duration_ms = end_time - start_time
          
          restore_info = %{
            backup_id: backup_id,
            restored_at: DateTime.utc_now(),
            duration_ms: duration_ms,
            metadata: metadata
          }
          
          new_state = update_stats(state, :restore_success, duration_ms)
          
          {:ok, restore_info, new_state}
        end
    end
  end

  defp export_antidote_data(client) do
    # Export all data from AntidoteDB
    # This is a simplified version - actual implementation would need to:
    # 1. Get all buckets
    # 2. Export all keys and values
    # 3. Export CRDT metadata
    
    try do
      # For now, we'll export the main bucket
      bucket = "mana_blockchain"
      
      # Get all keys (this would need pagination for large datasets)
      {:ok, keys} = AntidoteClient.list_keys(client, bucket)
      
      # Export key-value pairs
      data = Enum.reduce(keys, %{}, fn key, acc ->
        case AntidoteClient.get(client, bucket, key) do
          {:ok, value} -> Map.put(acc, key, value)
          _ -> acc
        end
      end)
      
      {:ok, %{
        version: @snapshot_format_version,
        bucket: bucket,
        data: data,
        exported_at: DateTime.utc_now()
      }}
    rescue
      e -> {:error, e}
    end
  end

  defp import_antidote_data(client, backup_data) do
    # Import data back to AntidoteDB
    bucket = backup_data.bucket || "mana_blockchain"
    
    # Clear existing data (optional, depends on restore strategy)
    # This should be configurable
    
    # Import key-value pairs
    Enum.each(backup_data.data, fn {key, value} ->
      AntidoteClient.put!(client, bucket, key, value)
    end)
    
    :ok
  end

  defp create_antidote_snapshot(client) do
    # Create a consistent snapshot using AntidoteDB's snapshot capabilities
    # This would use AntidoteDB's native snapshot mechanism
    {:ok, %{
      snapshot_id: generate_snapshot_id(),
      timestamp: DateTime.utc_now(),
      # Additional snapshot data
    }}
  end

  defp write_backup_data(path, data) do
    file_path = Path.join(path, "data.etf")
    binary_data = :erlang.term_to_binary(data, [:compressed])
    File.write!(file_path, binary_data)
    :ok
  end

  defp read_backup_data(path) do
    file_path = Path.join(path, "data.etf")
    
    case File.read(file_path) do
      {:ok, binary_data} ->
        data = :erlang.binary_to_term(binary_data)
        {:ok, data}
      error ->
        error
    end
  end

  defp write_backup_metadata(path, description, data) do
    metadata = %{
      version: @snapshot_format_version,
      description: description,
      created_at: DateTime.utc_now(),
      data_size: map_size(data[:data] || %{}),
      node_info: node_info()
    }
    
    file_path = Path.join(path, "metadata.json")
    json_data = Jason.encode!(metadata, pretty: true)
    File.write!(file_path, json_data)
    :ok
  end

  defp write_snapshot_metadata(path, name, description) do
    metadata = %{
      version: @snapshot_format_version,
      name: name,
      description: description,
      created_at: DateTime.utc_now(),
      type: "snapshot",
      node_info: node_info()
    }
    
    file_path = Path.join(path, "metadata.json")
    json_data = Jason.encode!(metadata, pretty: true)
    File.write!(file_path, json_data)
    :ok
  end

  defp read_backup_metadata(path) do
    file_path = Path.join(path, "metadata.json")
    
    with {:ok, json_data} <- File.read(file_path),
         {:ok, metadata} <- Jason.decode(json_data) do
      {:ok, metadata}
    end
  end

  defp write_snapshot_data(path, snapshot_data) do
    file_path = Path.join(path, "snapshot.etf")
    binary_data = :erlang.term_to_binary(snapshot_data, [:compressed])
    File.write!(file_path, binary_data)
    :ok
  end

  defp get_antidote_connection do
    # Get connection from pool or create new one
    case Process.whereis(AntidoteConnectionPool) do
      nil ->
        # Pool not running, create direct connection
        AntidoteClient.start_link([{127, 0, 0, 1}], 8087)
      
      _pid ->
        # Use connection from pool
        AntidoteConnectionPool.checkout()
    end
  end

  defp generate_backup_id do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    "backup_#{timestamp}_#{:rand.uniform(9999)}"
  end

  defp generate_snapshot_id do
    "snapshot_#{System.os_time(:second)}_#{:rand.uniform(9999)}"
  end

  defp calculate_backup_size(path) do
    path
    |> File.ls!()
    |> Enum.map(fn file ->
      Path.join(path, file)
      |> File.stat!()
      |> Map.get(:size, 0)
    end)
    |> Enum.sum()
  end

  defp list_available_backups(state) do
    backup_dir = state.backup_dir
    
    # List regular backups
    backups = 
      Path.join(backup_dir, "backup_*")
      |> Path.wildcard()
      |> Enum.map(&load_backup_info/1)
      |> Enum.reject(&is_nil/1)
    
    # List snapshots
    snapshots = 
      Path.join([backup_dir, "snapshots", "snapshot_*"])
      |> Path.wildcard()
      |> Enum.map(&load_backup_info/1)
      |> Enum.reject(&is_nil/1)
    
    # Sort by timestamp (newest first)
    (backups ++ snapshots)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  defp load_backup_info(path) do
    with {:ok, metadata} <- read_backup_metadata(path) do
      %{
        id: Path.basename(path),
        path: path,
        description: metadata["description"],
        timestamp: metadata["created_at"],
        type: metadata["type"] || "backup",
        size_bytes: calculate_backup_size(path)
      }
    else
      _ -> nil
    end
  end

  defp load_backup_metadata(state) do
    backups = list_available_backups(state)
    
    total_size = Enum.reduce(backups, 0, fn backup, acc ->
      acc + (backup.size_bytes || 0)
    end)
    
    %{state | 
      backup_history: backups,
      backup_count: length(backups),
      total_backup_size: total_size
    }
  end

  defp find_backup_path(state, backup_id) do
    backup = Enum.find(state.backup_history, fn b ->
      b.id == backup_id || b[:name] == backup_id
    end)
    
    backup && backup.path
  end

  defp cleanup_old_backups(state) do
    # Keep only the most recent backups
    backups = 
      state.backup_history
      |> Enum.filter(& &1[:type] != "snapshot")  # Don't delete snapshots
      |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    
    if length(backups) > state.max_backups do
      # Delete old backups
      backups
      |> Enum.drop(state.max_backups)
      |> Enum.each(fn backup ->
        Logger.info("Deleting old backup: #{backup.id}")
        File.rm_rf(backup.path)
      end)
      
      # Update state
      load_backup_metadata(state)
    else
      state
    end
  end

  defp schedule_next_backup(interval_ms) do
    Process.send_after(self(), :scheduled_backup, interval_ms)
  end

  defp schedule_cleanup do
    # Cleanup old backups every 6 hours
    Process.send_after(self(), :cleanup_old_backups, 6 * 3600 * 1000)
  end

  defp update_stats(state, event, duration_ms \\ 0) do
    stats = 
      case event do
        :backup_success ->
          state.stats
          |> Map.update!(:successful_backups, &(&1 + 1))
          |> Map.update!(:total_backup_time_ms, &(&1 + duration_ms))
        
        :backup_failed ->
          Map.update!(state.stats, :failed_backups, &(&1 + 1))
        
        :restore_success ->
          state.stats
          |> Map.update!(:successful_restores, &(&1 + 1))
          |> Map.update!(:total_restore_time_ms, &(&1 + duration_ms))
        
        :restore_failed ->
          Map.update!(state.stats, :failed_restores, &(&1 + 1))
      end
    
    %{state | stats: stats}
  end

  defp compile_stats(state) do
    avg_backup_time = 
      if state.stats.successful_backups > 0 do
        state.stats.total_backup_time_ms / state.stats.successful_backups
      else
        0
      end
    
    avg_restore_time = 
      if state.stats.successful_restores > 0 do
        state.stats.total_restore_time_ms / state.stats.successful_restores
      else
        0
      end
    
    Map.merge(state.stats, %{
      total_backups: state.backup_count,
      total_size_mb: state.total_backup_size / 1_048_576,
      last_backup: state.last_backup,
      avg_backup_time_ms: avg_backup_time,
      avg_restore_time_ms: avg_restore_time,
      backup_success_rate: calculate_success_rate(
        state.stats.successful_backups,
        state.stats.failed_backups
      ),
      restore_success_rate: calculate_success_rate(
        state.stats.successful_restores,
        state.stats.failed_restores
      )
    })
  end

  defp calculate_success_rate(success, failure) do
    total = success + failure
    if total > 0 do
      (success / total) * 100
    else
      0.0
    end
  end

  defp node_info do
    %{
      node: node(),
      hostname: :inet.gethostname() |> elem(1) |> to_string(),
      otp_release: :erlang.system_info(:otp_release) |> to_string(),
      elixir_version: System.version()
    }
  end
end