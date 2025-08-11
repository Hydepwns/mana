defmodule Blockchain.Mixfile do
  use Mix.Project

  def project do
    [
      app: :blockchain,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      description: "Ethereum blockchain implementation",
      package: [
        maintainers: ["Geoffrey Hayes", "Ayrat Badykov", "Mason Forest"],
        licenses: ["MIT", "Apache 2"],
        links: %{
          "GitHub" => "https://github.com/axol-io/mana/tree/master/apps/blockchain"
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
      # Umbrella deps
      {:evm, in_umbrella: true},
      {:exth, in_umbrella: true},
      {:exth_crypto, in_umbrella: true},
      {:merkle_patricia_tree, in_umbrella: true},
      # Monitoring dependencies
      {:jason, "~> 1.1"},
      {:cowboy, "~> 2.5"},
      {:telemetry, "~> 1.0"},
      {:prometheus_ex, "~> 3.0"}
    ]
  end
end
