defmodule Lotus.MixProject do
  use Mix.Project

  @source_url "https://github.com/typhoonworks/lotus"
  @version "0.4.0"

  def project do
    [
      app: :lotus,
      name: "Lotus",
      version: @version,
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      docs: docs(),
      package: package(),
      description: description(),
      source_url: @source_url,
      homepage_url: @source_url,
      dialyzer: dialyzer()
    ]
  end

  def cli do
    [preferred_envs: ["test.setup": :test, test: :test]]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto, "~> 3.10"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, "~> 0.20", optional: true},
      # {:myxql, "~> 0.7", optional: true},ie
      {:ecto_sqlite3, "~> 0.21", optional: true},
      {:nimble_options, "~> 1.0"},
      {:jason, "~> 1.4"},

      # Development and testing dependencies
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: [:dev, :test], runtime: false},
      {:mimic, "~> 2.0", only: :test}
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "test.setup": ["ecto.drop --quiet", "ecto.create", "ecto.migrate"],
      lint: ["format", "dialyzer"]
    ]
  end

  defp package do
    [
      name: "lotus",
      maintainers: ["Rui Freitas"],
      licenses: ["MIT"],
      links: %{GitHub: @source_url},
      files: ~w[lib .formatter.exs mix.exs README* LICENSE*]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit, :ecto, :ecto_sql, :postgrex],
      plt_core_path: "_build/#{Mix.env()}",
      flags: [:error_handling, :missing_return, :underspecs],
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: docs_guides(),
      groups_for_modules: [
        Core: [Lotus, Lotus.Config],
        Storage: [Lotus.Storage, Lotus.Storage.Query],
        Execution: [Lotus.Runner, Lotus.QueryResult],
        Migrations: [Lotus.Migrations, ~r/Lotus\.Migrations\..+/],
        Utilities: [Lotus.Json]
      ]
    ]
  end

  defp docs_guides do
    [
      "README.md",
      "guides/overview.md",
      "guides/installation.md",
      "guides/getting-started.md",
      "guides/configuration.md",
      "guides/contributing.md"
    ]
  end

  defp description do
    """
    Lightweight, SQL query runner and storage for Elixir apps — save, organize, and execute analytical queries with Ecto.
    """
  end
end
