defmodule Mix.Tasks.Ct do
  use Mix.Task

  # Suppress undefined function warning - :ct module availability is checked at runtime
  @compile {:no_warn_undefined, {:ct, :run_test, 1}}

  @shortdoc "Run the project's Common Test suite"

  @moduledoc """
  # Command line options

    * `--log-dir` - change the output directory; default: ctest/logs
    * other options supported by `compile*` tasks

  """

  def run(args) do
    {opts, args, rem_opts} = OptionParser.parse(args, strict: [log_dir: :string])
    new_args = args ++ MixErlangTasks.Util.filter_opts(rem_opts)

    Mix.env :test

    Mix.Task.run "compile", new_args

    # This is run independently, so that the test modules don't end up in the
    # .app file
    ebin_dir = Path.join([Mix.Project.app_path, "test_beams"])
    MixErlangTasks.Util.compile_files(Path.wildcard("ctest/**/*_SUITE.erl"), ebin_dir)

    logdir = Keyword.get(opts, :log_dir, "ctest/logs")
    File.mkdir_p!(logdir)

    # Check if :ct module is available (part of common_test application)
    if Code.ensure_loaded?(:ct) do
      :ct.run_test [
        {:dir, String.to_charlist(ebin_dir)},
        {:logdir, String.to_charlist(logdir)},
        {:auto_compile, false}
      ]
    else
      Mix.raise "Common Test (:ct) module not available. Please ensure :common_test is included in your dependencies."
    end
  end
end
