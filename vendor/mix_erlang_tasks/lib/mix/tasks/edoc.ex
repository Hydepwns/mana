defmodule Mix.Tasks.Edoc do
  use Mix.Task

  # Suppress undefined function warning - :edoc module availability is checked at runtime
  @compile {:no_warn_undefined, {:edoc, :application, 3}}

  @shortdoc "Generate edoc documentation from the source"

  def run(_args) do
    # Check if :edoc module is available
    if Code.ensure_loaded?(:edoc) do
      try do
        :edoc.application(Mix.Project.config[:app], ~c".", [])
      catch
        :exit, _reason -> Mix.raise "Encountered some errors."
      end

      Mix.shell.info [:green, "Docs successfully generated."]
      Mix.shell.info [:green, "View them at doc/index.html."]
    else
      Mix.raise "EDoc (:edoc) module not available. Please ensure :edoc is included in your dependencies."
    end
  end
end
