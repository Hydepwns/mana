defmodule JSONRPC2.Mixfile do
  use Mix.Project

  def project do
    [
      app: :jsonrpc2,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      description: "JSON-RPC 2.0 implementation for Ethereum",
      package: [
        maintainers: ["DROO", "Geoffrey Hayes", "Ayrat Badykov", "Mason Forest"],
        licenses: ["MIT", "Apache 2"],
        links: %{
          "GitHub" => "https://github.com/axol-io/mana/tree/master/apps/jsonrpc2"
        }
      ],
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps()
      # Temporarily disabled warnings-as-errors to allow compilation
      # elixirc_options: [warnings_as_errors: true]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      # External deps
      {:cowboy, "~> 2.5"},
      {:jason, "~> 1.1"},
      {:ranch, "~> 1.6"},
      {:plug, "~> 1.7"},
      {:plug_cowboy, "~> 2.0"},
      # Umbrella deps
      {:blockchain, in_umbrella: true},
      {:exth, in_umbrella: true},
      {:exth_crypto, in_umbrella: true},
      {:merkle_patricia_tree, in_umbrella: true}
    ]
  end
end
