defmodule EVM.Mixfile do
  use Mix.Project

  def project do
    [
      app: :evm,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      description: "Ethereum Virtual Machine implementation",
      package: [
        maintainers: ["DROO", "Geoffrey Hayes", "Ayrat Badykov", "Mason Forest"],
        licenses: ["MIT", "Apache 2"],
        links: %{
          "GitHub" =>
            "https://github.com/axol-io/mana/tree/master/apps/evm"
        }
      ],
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
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
      {:decimal, "~> 1.5.0"},
      {:ex_rlp, "~> 0.6"},
      {:bn, "~> 0.2.1"},
      # Umbrella deps
      {:exth, in_umbrella: true},
      {:exth_crypto, in_umbrella: true},
      {:merkle_patricia_tree, in_umbrella: true}
    ]
  end
end
