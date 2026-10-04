[
  import_deps: [:ecto, :ecto_sql, :phoenix, :typelizer],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  line_length: 100,
  inputs: ["*.{heex,ex,exs}", "{config,lib,test,credo}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
