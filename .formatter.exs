[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  subdirectories: ["priv/repo/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  attribute_formatters: %{class: CanonicalTailwind},
  inputs: [
    "*.{heex,ex,exs}",
    "{config,lib,test}/**/*.{heex,ex,exs}",
    "priv/*/seeds.exs",
    "priv/repo/scripts/**/*.{ex,exs}"
  ]
]
