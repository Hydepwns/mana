defmodule Mix.Tasks.MigrateToAntidote do
  @moduledoc """
  Mix task for migrating ETS storage to AntidoteDB.
  
  Usage:
    mix migrate_to_antidote [options]
    
  Options:
    --ets-table TABLE       ETS table name to migrate from (required)
    --antidote-bucket NAME  AntidoteDB bucket name (default: "ethereum_state")
    --batch-size SIZE       Number of records per batch (default: 1000)
    --checkpoint-interval N Save progress every N records (default: 10000)
    --dry-run              Simulate migration without writing data
    --verify               Verify migration after completion
    --verbose              Enable verbose logging
    --help                 Show this help message
    
  Examples:
    # Basic migration
    mix migrate_to_antidote --ets-table merkle_patricia_tree
    
    # Dry run with verbose output
    mix migrate_to_antidote --ets-table merkle_patricia_tree --dry-run --verbose
    
    # Migration with verification
    mix migrate_to_antidote --ets-table merkle_patricia_tree --verify
    
    # Resume interrupted migration
    mix migrate_to_antidote --ets-table merkle_patricia_tree
    # (will automatically resume from checkpoint if exists)
  """
  
  use Mix.Task
  alias MerklePatriciaTree.DB.Migration.ETSToAntidote
  alias MerklePatriciaTree.DB.{ETS, Antidote}
  require Logger
  
  @shortdoc "Migrate ETS storage to AntidoteDB"
  
  @impl Mix.Task
  def run(args) do
    # Start applications
    Mix.Task.run("app.start")
    
    # Parse arguments
    {opts, _, _} = OptionParser.parse(args,
      strict: [
        ets_table: :string,
        antidote_bucket: :string,
        batch_size: :integer,
        checkpoint_interval: :integer,
        dry_run: :boolean,
        verify: :boolean,
        verbose: :boolean,
        help: :boolean
      ],
      aliases: [
        h: :help,
        v: :verbose,
        d: :dry_run
      ]
    )
    
    if opts[:help] do
      Mix.shell().info(@moduledoc)
      System.halt(0)
    end
    
    # Validate required arguments
    ets_table = case opts[:ets_table] do
      nil ->
        Mix.raise("ETS table name is required. Use --ets-table TABLE")
      table ->
        String.to_atom(table)
    end
    
    antidote_bucket = opts[:antidote_bucket] || "ethereum_state"
    
    # Configure logging
    if opts[:verbose] do
      Logger.configure(level: :debug)
    end
    
    # Initialize storage backends
    Mix.shell().info("Initializing storage backends...")
    
    ets_ref = {MerklePatriciaTree.DB.ETS, ets_table}
    antidote_ref = Antidote.init(antidote_bucket)
    
    # Ensure AntidoteDB connection pool is started
    ensure_antidote_pool_started()
    
    # Prepare migration options
    migration_opts = [
      batch_size: opts[:batch_size] || 1000,
      checkpoint_interval: opts[:checkpoint_interval] || 10_000,
      dry_run: opts[:dry_run] || false,
      verbose: opts[:verbose] || false
    ]
    
    if opts[:dry_run] do
      Mix.shell().info("Running in DRY RUN mode - no data will be written")
    end
    
    # Perform migration
    Mix.shell().info("Starting migration from ETS table '#{ets_table}' to AntidoteDB bucket '#{antidote_bucket}'...")
    
    case ETSToAntidote.migrate(ets_ref, antidote_ref, migration_opts) do
      {:ok, stats} ->
        Mix.shell().info("""
        
        Migration completed successfully!
        
        Statistics:
          Total records: #{stats.total}
          Processed: #{stats.processed}
          Succeeded: #{stats.succeeded}
          Failed: #{stats.failed}
          Skipped: #{stats.skipped}
          Time elapsed: #{format_duration(stats.elapsed_ms)}
          Rate: #{stats.rate_per_sec} records/sec
        """)
        
        # Optionally verify migration
        if opts[:verify] do
          Mix.shell().info("\nVerifying migration...")
          
          case ETSToAntidote.verify_migration(ets_ref, antidote_ref, verbose: opts[:verbose]) do
            {:ok, verify_stats} ->
              Mix.shell().info("""
              Verification successful!
                Sample size: #{verify_stats.sample_size}
                Mismatches: #{verify_stats.mismatches}
              """)
              
            {:error, verify_error} ->
              Mix.shell().error("""
              Verification failed!
                Sample size: #{verify_error.sample_size}
                Mismatches: #{verify_error.mismatches}
                
              Example mismatches:
              #{format_mismatches(verify_error.examples)}
              """)
              System.halt(1)
          end
        end
        
      {:error, %{reason: reason, stats: stats}} ->
        Mix.shell().error("""
        
        Migration failed!
        
        Error: #{inspect(reason)}
        
        Partial statistics:
          Processed: #{stats.processed}/#{stats.total}
          Succeeded: #{stats.succeeded}
          Failed: #{stats.failed}
          
        You can resume the migration by running the same command again.
        The migration will continue from the last checkpoint.
        """)
        System.halt(1)
        
      {:error, reason} ->
        Mix.shell().error("Migration failed: #{inspect(reason)}")
        System.halt(1)
    end
  end
  
  defp ensure_antidote_pool_started do
    case Process.whereis(MerklePatriciaTree.DB.AntidoteConnectionPool) do
      nil ->
        {:ok, _} = MerklePatriciaTree.DB.AntidoteConnectionPool.start_link(
          nodes: [
            {"localhost", 8087},
            {"localhost", 8088},
            {"localhost", 8089}
          ],
          pool_size: 10
        )
        Mix.shell().info("Started AntidoteDB connection pool")
        
      _pid ->
        Mix.shell().info("AntidoteDB connection pool already running")
    end
  end
  
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000 do
    seconds = Float.round(ms / 1000, 1)
    "#{seconds}s"
  end
  defp format_duration(ms) do
    minutes = div(ms, 60_000)
    seconds = rem(ms, 60_000) |> div(1000)
    "#{minutes}m #{seconds}s"
  end
  
  defp format_mismatches(examples) do
    Enum.map_join(examples, "\n", fn {key, ets_val, ant_val} ->
      "  Key: #{inspect(key)}\n" <>
      "    ETS: #{inspect(ets_val)}\n" <>
      "    AntidoteDB: #{inspect(ant_val)}"
    end)
  end
end