defmodule Mix.Tasks.AntidoteBackup do
  @moduledoc """
  Mix task for managing AntidoteDB backups and snapshots.
  
  ## Usage
  
      mix antidote_backup [command] [options]
  
  ## Commands
  
    * `backup` - Create an immediate backup
    * `snapshot` - Create a named snapshot
    * `restore` - Restore from a backup or snapshot
    * `list` - List available backups and snapshots
    * `stats` - Show backup statistics
    * `cleanup` - Remove old backups
  
  ## Examples
  
      # Create a backup
      mix antidote_backup backup --description "Before upgrade"
      
      # Create a snapshot
      mix antidote_backup snapshot --name "v1.0-release" --description "Release version 1.0"
      
      # List backups
      mix antidote_backup list
      
      # Restore from backup
      mix antidote_backup restore --id backup_1234567890_1234
      
      # Show statistics
      mix antidote_backup stats
      
      # Cleanup old backups (keep last 10)
      mix antidote_backup cleanup --keep 10
  """

  use Mix.Task
  require Logger

  alias MerklePatriciaTree.DB.BackupManager

  @shortdoc "Manage AntidoteDB backups and snapshots"

  @switches [
    description: :string,
    name: :string,
    id: :string,
    keep: :integer,
    dir: :string,
    force: :boolean
  ]

  @aliases [
    d: :description,
    n: :name,
    i: :id,
    k: :keep,
    f: :force
  ]

  @impl Mix.Task
  def run(args) do
    {opts, args} = OptionParser.parse!(args, switches: @switches, aliases: @aliases)
    
    # Start necessary applications
    {:ok, _} = Application.ensure_all_started(:merkle_patricia_tree)
    
    # Start BackupManager if not running
    ensure_backup_manager_started(opts)
    
    # Execute command
    case args do
      ["backup" | _] -> handle_backup(opts)
      ["snapshot" | _] -> handle_snapshot(opts)
      ["restore" | _] -> handle_restore(opts)
      ["list" | _] -> handle_list(opts)
      ["stats" | _] -> handle_stats(opts)
      ["cleanup" | _] -> handle_cleanup(opts)
      [] -> show_help()
      _ -> 
        Mix.shell().error("Unknown command: #{Enum.join(args, " ")}")
        show_help()
    end
  end

  defp handle_backup(opts) do
    description = opts[:description] || "Manual backup via Mix task"
    
    Mix.shell().info("Creating backup...")
    
    case BackupManager.backup_now(description) do
      {:ok, backup_info} ->
        Mix.shell().info("""
        
        ✅ Backup completed successfully!
        
        ID:          #{backup_info.id}
        Path:        #{backup_info.path}
        Description: #{backup_info.description}
        Size:        #{format_size(backup_info.size_bytes)}
        Duration:    #{backup_info.duration_ms} ms
        Timestamp:   #{backup_info.timestamp}
        """)
      
      {:error, reason} ->
        Mix.shell().error("❌ Backup failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp handle_snapshot(opts) do
    name = opts[:name] || raise "Snapshot name is required (--name NAME)"
    description = opts[:description] || ""
    
    Mix.shell().info("Creating snapshot '#{name}'...")
    
    case BackupManager.create_snapshot(name, description) do
      {:ok, snapshot_info} ->
        Mix.shell().info("""
        
        ✅ Snapshot created successfully!
        
        ID:          #{snapshot_info.id}
        Name:        #{snapshot_info.name}
        Path:        #{snapshot_info.path}
        Description: #{snapshot_info.description}
        Size:        #{format_size(snapshot_info.size_bytes)}
        Timestamp:   #{snapshot_info.timestamp}
        """)
      
      {:error, reason} ->
        Mix.shell().error("❌ Snapshot creation failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp handle_restore(opts) do
    backup_id = opts[:id] || select_backup_interactively()
    
    unless opts[:force] do
      unless Mix.shell().yes?("⚠️  This will restore data from backup '#{backup_id}'. Continue?") do
        Mix.shell().info("Restore cancelled.")
        exit({:shutdown, 0})
      end
    end
    
    Mix.shell().info("Restoring from '#{backup_id}'...")
    
    case BackupManager.restore(backup_id) do
      {:ok, restore_info} ->
        Mix.shell().info("""
        
        ✅ Restore completed successfully!
        
        Backup ID:   #{restore_info.backup_id}
        Restored at: #{restore_info.restored_at}
        Duration:    #{restore_info.duration_ms} ms
        """)
      
      {:error, reason} ->
        Mix.shell().error("❌ Restore failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp handle_list(_opts) do
    backups = BackupManager.list_backups()
    
    if Enum.empty?(backups) do
      Mix.shell().info("No backups found.")
    else
      Mix.shell().info("""
      
      Available Backups and Snapshots
      ================================
      """)
      
      # Group by type
      {snapshots, regular_backups} = Enum.split_with(backups, & &1.type == "snapshot")
      
      # Display snapshots
      unless Enum.empty?(snapshots) do
        Mix.shell().info("📸 Snapshots:")
        Enum.each(snapshots, &display_backup_info/1)
        Mix.shell().info("")
      end
      
      # Display regular backups
      unless Enum.empty?(regular_backups) do
        Mix.shell().info("💾 Backups:")
        Enum.each(regular_backups, &display_backup_info/1)
      end
      
      # Summary
      total_size = Enum.reduce(backups, 0, & &1.size_bytes + &2)
      Mix.shell().info("""
      
      Total: #{length(backups)} backups (#{format_size(total_size)})
      """)
    end
  end

  defp handle_stats(_opts) do
    stats = BackupManager.get_stats()
    
    Mix.shell().info("""
    
    Backup Statistics
    =================
    
    📊 Backup Operations:
      Successful:      #{stats.successful_backups}
      Failed:          #{stats.failed_backups}
      Success Rate:    #{Float.round(stats.backup_success_rate, 1)}%
      Avg Duration:    #{Float.round(stats.avg_backup_time_ms, 1)} ms
    
    🔄 Restore Operations:
      Successful:      #{stats.successful_restores}
      Failed:          #{stats.failed_restores}
      Success Rate:    #{Float.round(stats.restore_success_rate, 1)}%
      Avg Duration:    #{Float.round(stats.avg_restore_time_ms, 1)} ms
    
    💾 Storage:
      Total Backups:   #{stats.total_backups}
      Total Size:      #{Float.round(stats.total_size_mb, 2)} MB
    """)
    
    if stats.last_backup do
      Mix.shell().info("""
      📅 Last Backup:
        ID:            #{stats.last_backup.id}
        Time:          #{stats.last_backup.timestamp}
        Size:          #{format_size(stats.last_backup.size_bytes)}
        Status:        #{stats.last_backup.status}
      """)
    end
  end

  defp handle_cleanup(opts) do
    keep = opts[:keep] || 10
    backups = BackupManager.list_backups()
    
    # Only consider non-snapshot backups for cleanup
    regular_backups = 
      backups
      |> Enum.filter(& &1.type != "snapshot")
      |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    
    to_delete = Enum.drop(regular_backups, keep)
    
    if Enum.empty?(to_delete) do
      Mix.shell().info("No backups to clean up.")
    else
      Mix.shell().info("""
      
      The following backups will be deleted:
      """)
      
      Enum.each(to_delete, &display_backup_info/1)
      
      total_size = Enum.reduce(to_delete, 0, & &1.size_bytes + &2)
      Mix.shell().info("""
      
      This will free up #{format_size(total_size)} of disk space.
      """)
      
      if Mix.shell().yes?("Continue with cleanup?") do
        Enum.each(to_delete, fn backup ->
          Mix.shell().info("Deleting #{backup.id}...")
          File.rm_rf!(backup.path)
        end)
        
        Mix.shell().info("✅ Cleanup completed.")
      else
        Mix.shell().info("Cleanup cancelled.")
      end
    end
  end

  defp display_backup_info(backup) do
    type_icon = if backup.type == "snapshot", do: "📸", else: "💾"
    
    Mix.shell().info("""
      #{type_icon} #{backup.id}
         Size:        #{format_size(backup.size_bytes)}
         Time:        #{format_timestamp(backup.timestamp)}
         Description: #{backup.description || "-"}
    """)
  end

  defp select_backup_interactively do
    backups = BackupManager.list_backups()
    
    if Enum.empty?(backups) do
      Mix.shell().error("No backups available to restore from.")
      exit({:shutdown, 1})
    end
    
    Mix.shell().info("Select a backup to restore:")
    
    Enum.with_index(backups, 1)
    |> Enum.each(fn {backup, index} ->
      Mix.shell().info("  #{index}. #{backup.id} (#{format_timestamp(backup.timestamp)})")
    end)
    
    selection = Mix.shell().prompt("Enter number (1-#{length(backups)}):")
    
    case Integer.parse(selection) do
      {num, ""} when num >= 1 and num <= length(backups) ->
        Enum.at(backups, num - 1).id
      
      _ ->
        Mix.shell().error("Invalid selection.")
        exit({:shutdown, 1})
    end
  end

  defp ensure_backup_manager_started(opts) do
    case Process.whereis(BackupManager) do
      nil ->
        backup_dir = opts[:dir] || "/var/backups/antidote"
        {:ok, _} = BackupManager.start_link(backup_dir: backup_dir)
      
      _pid ->
        :ok
    end
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes) when bytes < 1_073_741_824, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_073_741_824, 2)} GB"

  defp format_timestamp(nil), do: "-"
  defp format_timestamp(timestamp) when is_binary(timestamp), do: timestamp
  defp format_timestamp(%DateTime{} = dt), do: DateTime.to_string(dt)
  defp format_timestamp(_), do: "-"

  defp show_help do
    Mix.shell().info(@moduledoc)
  end
end