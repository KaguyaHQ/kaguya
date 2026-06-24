defmodule Kaguya.MixProject do
  use Mix.Project

  def project do
    [
      app: :kaguya,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Kaguya.Application, []},
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
      {:tidewave, "~> 0.5", only: [:dev]},
      {:igniter, "~> 0.6", override: true},
      {:bandit, "~> 1.11"},
      {:cachex, "~> 4.1"},
      {:cors_plug, "~> 3.0.3"},
      {:credo, "~> 1.7.18", only: [:dev, :test], runtime: false},
      {:dns_cluster, "~> 0.2"},
      {:dotenvy, "~> 1.1"},
      {:earmark, "~> 1.4"},
      {:ecto_sql, "~> 3.13"},
      {:ex_aws, "~> 2.7"},
      {:ex_aws_s3, "~> 2.5.9"},
      {:ex_image_info, "~> 1.0"},
      {:finch, "~> 0.22"},
      {:floki, "~> 0.38"},
      {:hammer, "~> 7.3"},
      {:image, "~> 0.67"},
      {:jason, "~> 1.4.4"},
      {:nimble_csv, "~> 1.2"},
      {:oban, "~> 2.22"},
      {:phoenix, "~> 1.8.0"},
      {:phoenix_ecto, "~> 4.7"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:phoenix_live_reload, "~> 1.6.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:phoenix_pubsub, "~> 2.2"},
      {:canonical_tailwind, "~> 0.2.0", only: [:dev, :test], runtime: false},
      {:plug, "~> 1.17"},
      {:postgrex, "~> 0.22"},
      {:req, "~> 0.5.8"},
      {:sentry, "~> 13.0"},
      {:slugify, "~> 1.3.1"},
      {:sweet_xml, "~> 0.7.5"},
      {:uuidv7, "~> 1.0"},

      # Prometheus metrics scraped by Grafana/Alloy
      {:prom_ex, "~> 1.11"},

      # Email
      {:swoosh, "~> 1.25"},
      {:gen_smtp, "~> 1.2"},

      # Numerical — powers the Nx port of the rec inference pipeline
      # (replacing the Python shell-out in prod). EXLA is the hot path:
      # stage1_ease_scores is a `defn`, JIT-compiled to fused XLA ops →
      # orders-of-magnitude faster than BinaryBackend's pure-Elixir
      # tensor walk. XLA ships a precompiled `x86_64-linux-gnu-cpu`
      # binary (matches the Hetzner/Ubuntu runtime) and
      # `aarch64-darwin-cpu` for local dev on Apple Silicon — no CUDA
      # required, no Bazel build. Adds ~150–200MB to the image; we
      # recover that by dropping Python + numpy/scipy once EXLA is live.
      {:nx, "~> 0.9"},
      {:exla, "~> 0.9"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:lazy_html, ">= 0.1.0"},
      # x-release-please-version
      {:lucide_icons, "~> 2.0"},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1}
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
      setup: ["deps.get", "ecto.setup", "assets.setup", "cmd sh scripts/setup-git-hooks.sh"],
      "ecto.setup": ["ecto.create", "ecto.load --skip-if-loaded", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.load --skip-if-loaded --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": [
        "tailwind.install --if-missing",
        "esbuild.install --if-missing",
        "cmd npm install --prefix assets --no-audit --no-fund"
      ],
      "assets.build": [
        "tailwind kaguya",
        "esbuild kaguya",
        "esbuild list_layout_island",
        "esbuild favorites_dnd_island"
      ],
      "assets.deploy": [
        "tailwind kaguya --minify",
        # `--sourcemap=linked` writes app.js.map alongside app.js with a
        # `//# sourceMappingURL=app.js.map` comment in the bundle. Sentry's
        # browser SDK + dev tools fetch the map at error time, so production
        # stack traces resolve back to original source. Maps are served
        # publicly via Plug.Static — acceptable trade-off for this repo;
        # see docs/operations/observability/source-maps.md for the private-upload path.
        "esbuild kaguya --minify --sourcemap=linked",
        "esbuild list_layout_island --minify --sourcemap=linked",
        "esbuild favorites_dnd_island --minify --sourcemap=linked",
        "phx.digest"
      ]
    ]
  end
end
