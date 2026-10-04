defmodule StarterKit.MixProject do
  use Mix.Project

  def project do
    [
      app: :starter_kit,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:boundary, :phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      boundary: [default: [check: [aliases: true]]],
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts",
        flags: [:error_handling, :extra_return, :missing_return, :underspecs]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {StarterKit.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [preferred_envs: [check: :test, precommit: :test]]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:bcrypt_elixir, "~> 3.0"},
      {:phoenix, "~> 1.8.4"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:oban, "~> 2.24"},
      {:oban_web, "~> 2.13"},
      {:hammer, "~> 7.5"},
      {:sentry, "~> 13.5"},
      {:ueberauth, "~> 0.10"},
      {:ueberauth_google, "~> 0.12"},
      {:ex_aws, "~> 2.7"},
      {:ex_aws_s3, "~> 2.5"},
      {:nimble_csv, "~> 1.3"},
      {:remote_ip, "~> 1.2"},
      {:boundary, "~> 0.11", runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.15", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.17", only: [:dev, :test], runtime: false},
      # Type contract (serializers → TypeScript). docs/TYPE_CONTRACT.md
      {:typelizer, path: "../typelizer-ex"}
      # Swap back to {:typelizer, "~> 0.2"} once controller-path naming is released on Hex.
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
      setup: [
        "deps.get",
        "cmd pnpm install",
        "cmd git config core.hooksPath .githooks",
        "ecto.setup"
      ],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "i18n.sync": ["run -e 'IO.inspect(StarterKit.I18n.sync(), label: \"i18n sync\")'"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "frontend.build": ["cmd pnpm install --frozen-lockfile", "cmd pnpm build"],
      "frontend.deploy": ["frontend.build"]
    ]
  end
end
