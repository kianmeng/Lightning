defmodule Lightning.MixProject do
  use Mix.Project

  def project do
    [
      app: :lightning,
      version: "0.1.0",
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:gettext] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Lightning.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:credo, "~> 1.6", only: [:test, :dev]},
      {:dialyxir, "~> 1.1", only: [:test, :dev]},
      {:ecto_sql, "~> 3.6"},
      {:esbuild, "~> 0.3", runtime: Mix.env() == :dev},
      {:excoveralls, "~> 0.14.4", only: [:test, :dev]},
      {:floki, ">= 0.30.0", only: :test},
      {:gettext, "~> 0.18"},
      {:httpoison, "~> 1.8"},
      {:jason, "~> 1.2"},
      {:junit_formatter, "~> 3.0", only: [:test]},
      {:mimic, "~> 1.7", only: :test},
      {:mix_test_watch, "~> 1.0", only: [:test, :dev], runtime: false},
      {:phoenix_ecto, "~> 4.4"},
      {:phoenix_html, "~> 3.0"},
      {:phoenix_live_dashboard, "~> 0.6"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.17.5"},
      {:phoenix, "~> 1.6.6"},
      {:plug_cowboy, "~> 2.5"},
      {:postgrex, ">= 0.0.0"},
      {:sobelow, "~> 0.11.1", only: [:test, :dev]},
      {:swoosh, "~> 1.3"},
      {:tailwind, "~> 0.1", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.deploy": ["esbuild default --minify", "phx.digest"]
    ]
  end
end
