#!/usr/bin/env elixir

# Comprehensive Pruning Test Runner Script
# Usage: elixir scripts/testing/run_pruning_tests.exs [options]

defmodule PruningTestScript do
  @moduledoc """
  Script to run comprehensive pruning tests with various options.
  
  Options:
    --suite SUITE     Run specific test suite (functional, stress, benchmark, production, full)
    --scale SCALE     Dataset scale (small, medium, large, massive) 
    --ci              Run in CI mode with reduced scope
    --benchmark       Run performance benchmarks only
    --production      Validate production readiness
    --output DIR      Output directory for results
    --help            Show this help message
  """
  
  def main(args) do
    IO.puts("🚀 Ethereum 2.0 Pruning System Test Runner")
    IO.puts("==========================================")
    
    options = parse_args(args)
    
    if options[:help] do
      show_help()
      System.halt(0)
    end
    
    # Set up Mix environment
    Mix.install([
      {:ex_unit, "~> 1.0"},
      {:jason, "~> 1.4"}
    ])
    
    # Load the Mana application code
    Code.require_file("apps/ex_wire/lib/ex_wire/eth2/pruning_test_runner.ex")
    Code.require_file("apps/ex_wire/lib/ex_wire/eth2/test_data_generator.ex")
    Code.require_file("apps/ex_wire/lib/ex_wire/eth2/pruning_benchmark.ex")
    
    # Configure test environment based on options
    configure_test_environment(options)
    
    # Run the requested test suite
    result = case options[:mode] do
      :ci -> 
        IO.puts("🔧 Running CI validation...")
        ExWire.Eth2.PruningTestRunner.run_ci_validation(options)
      
      :benchmark ->
        IO.puts("📊 Running performance benchmarks...")
        ExWire.Eth2.PruningBenchmark.run_full_benchmark(options)
      
      :production ->
        IO.puts("🏭 Validating production readiness...")
        ExWire.Eth2.PruningTestRunner.validate_production_readiness(options)
      
      :suite ->
        suite = options[:suite]
        IO.puts("🧪 Running #{suite} test suite...")
        ExWire.Eth2.PruningTestRunner.run_test_suite(suite, options)
      
      :full ->
        IO.puts("🎯 Running comprehensive test suite...")
        ExWire.Eth2.PruningTestRunner.run_full_test_suite(options)
    end
    
    # Display results and exit with appropriate code
    display_final_results(result)
    exit_with_status(result)
  end
  
  defp parse_args(args) do
    {options, _remaining, _invalid} = OptionParser.parse(args, [
      switches: [
        suite: :string,
        scale: :string,
        ci: :boolean,
        benchmark: :boolean,
        production: :boolean,
        output: :string,
        help: :boolean
      ],
      aliases: [
        s: :suite,
        o: :output,
        h: :help
      ]
    ])
    
    # Determine mode based on options
    mode = cond do
      options[:ci] -> :ci
      options[:benchmark] -> :benchmark
      options[:production] -> :production
      options[:suite] -> :suite
      true -> :full
    end
    
    # Set defaults
    options = Keyword.merge([
      mode: mode,
      scale: "medium",
      output_dir: "test_results_#{DateTime.utc_now() |> DateTime.to_unix()}"
    ], options)
    
    # Validate suite option
    if options[:suite] and options[:suite] not in ["functional", "stress", "benchmark", "production"] do
      IO.puts("❌ Error: Invalid suite '#{options[:suite]}'. Must be one of: functional, stress, benchmark, production")
      System.halt(1)
    end
    
    # Convert suite to atom if provided
    if options[:suite] do
      options = Keyword.put(options, :suite, String.to_atom(options[:suite]))
    end
    
    options
  end
  
  defp configure_test_environment(options) do
    # Set scale environment variable
    if options[:scale] do
      System.put_env("PRUNING_TEST_SCALE", options[:scale])
      IO.puts("📏 Test scale: #{options[:scale]}")
    end
    
    # Set CI mode if requested
    if options[:mode] == :ci do
      System.put_env("PRUNING_CI_MODE", "true")
      IO.puts("🤖 CI mode enabled")
    end
    
    # Create output directory
    if options[:output_dir] do
      File.mkdir_p!(options[:output_dir])
      IO.puts("📁 Output directory: #{options[:output_dir]}")
    end
    
    IO.puts("")
  end
  
  defp show_help do
    IO.puts(@moduledoc)
    IO.puts("""
    
    Examples:
      # Run all tests
      elixir scripts/testing/run_pruning_tests.exs
      
      # Run only functional tests
      elixir scripts/testing/run_pruning_tests.exs --suite functional
      
      # Run stress tests with large dataset
      elixir scripts/testing/run_pruning_tests.exs --suite stress --scale large
      
      # Run CI validation
      elixir scripts/testing/run_pruning_tests.exs --ci
      
      # Run benchmarks only
      elixir scripts/testing/run_pruning_tests.exs --benchmark
      
      # Validate production readiness
      elixir scripts/testing/run_pruning_tests.exs --production
      
      # Custom output directory
      elixir scripts/testing/run_pruning_tests.exs --output my_results
    """)
  end
  
  defp display_final_results(result) do
    IO.puts("")
    IO.puts("=" * 50)
    IO.puts("FINAL RESULTS")
    IO.puts("=" * 50)
    
    case result do
      {:ok, message} ->
        IO.puts("✅ SUCCESS: #{message}")
        
      {:warning, message} ->
        IO.puts("⚠️  WARNING: #{message}")
        
      {:error, message} ->
        IO.puts("❌ FAILURE: #{message}")
        
      %{overall_summary: summary} ->
        # Comprehensive test results
        status_icon = case summary.overall_status do
          :pass -> "✅"
          :warning -> "⚠️ "
          :fail -> "❌"
        end
        
        IO.puts("#{status_icon} Overall Status: #{String.upcase(to_string(summary.overall_status))}")
        IO.puts("📊 Success Rate: #{Float.round(summary.success_rate, 1)}%")
        IO.puts("🧪 Suites: #{summary.passed_suites}/#{summary.total_suites} passed")
        
      _ ->
        IO.puts("✅ Test execution completed")
    end
    
    IO.puts("=" * 50)
  end
  
  defp exit_with_status(result) do
    exit_code = case result do
      {:ok, _} -> 0
      {:warning, _} -> 0  # Warnings don't fail CI
      {:error, _} -> 1
      %{overall_summary: %{overall_status: :pass}} -> 0
      %{overall_summary: %{overall_status: :warning}} -> 0
      %{overall_summary: %{overall_status: :fail}} -> 1
      _ -> 0
    end
    
    if exit_code == 0 do
      IO.puts("🎉 All tests completed successfully!")
    else
      IO.puts("💥 Tests failed - see output above for details")
    end
    
    System.halt(exit_code)
  end
end

# Run the script
PruningTestScript.main(System.argv())