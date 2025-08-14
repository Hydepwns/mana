defmodule Mix.Tasks.Eunit do
  use Mix.Task

  # Suppress undefined function warning - :eunit module availability is checked at runtime
  @compile {:no_warn_undefined, {:eunit, :test, 2}}

  @shortdoc "Run the project's EUnit test suite"

  @moduledoc """
  # Command line options

    * `--verbose`, `-v` - verbose mode
    * other options supported by `compile*` tasks

  """

  def run(args) do
    {opts, args, rem_opts} = OptionParser.parse(args, strict: [verbose: :boolean], aliases: [v: :verbose])
    new_args = args ++ MixErlangTasks.Util.filter_opts(rem_opts)

    # use a different env from :test because compilation options differ
    Mix.env :etest

    compile_opts = [{:d,:TEST}|Mix.Project.config[:erlc_options]]
    System.put_env "ERL_COMPILER_OPTIONS", format_compile_opts(compile_opts)

    Mix.Task.run "compile", new_args

    # This is run independently, so that the test modules don't end up in the
    # .app file
    ebin_test = Path.join([Mix.Project.app_path, "test_beams"])
    MixErlangTasks.Util.compile_files(Path.wildcard("etest/**/*_tests.erl"), ebin_test)

    options = if Keyword.get(opts, :verbose, false), do: [:verbose], else: []
    
    # Check if :eunit module is available
    if Code.ensure_loaded?(:eunit) do
      :eunit.test {:application, Mix.Project.config[:app]}, options
    else
      Mix.raise "EUnit (:eunit) module not available. Please ensure :eunit is included in your dependencies."
    end
  end

  defp format_compile_opts(opts) do
    :io_lib.format("~p", [opts]) |> List.to_string
  end
end
