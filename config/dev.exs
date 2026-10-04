import Config

# Parallel lanes (docs/GATES.md): each checkout may set its own PORT, VITE_PORT, PGDATABASE
# and POOL_SIZE, so two apps or two worktrees run side by side.
port = String.to_integer(System.get_env("PORT", "4000"))

config :starter_kit, StarterKit.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: System.get_env("PGDATABASE", "starter_kit_dev"),
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

# Vite serves the assets in dev (HMR). `mix phx.server` starts it as a watcher.

# VITE_PORT lets several apps run side by side (each product picks its own).
config :starter_kit,
  vite_dev_server: "http://127.0.0.1:#{System.get_env("VITE_PORT", "5173")}",
  public_url: "http://localhost:#{port}"

secret_key_base = "IK34GtO2aRLsEJJ99CXlI8eCtusNsejFq+cyG4kDFKaJhI0Y0dqNvQRlhLJ8aXUi"

# Signed tokens outside the web layer (Notifications: unsubscribe links).
config :starter_kit, :secret_key_base, secret_key_base

config :starter_kit, StarterKitWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: port],
  url: [host: "localhost", port: port],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: secret_key_base,
  watchers: [
    pnpm: [
      "dev",
      "--host",
      "127.0.0.1",
      "--port",
      System.get_env("VITE_PORT", "5173"),
      cd: Path.expand("..", __DIR__)
    ]
  ]

config :starter_kit, StarterKitWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"lib/starter_kit_web/router\.ex$"E,
      ~r"lib/starter_kit_web/(controllers|components)/.*\.(ex|heex)$"E
    ]
  ]

config :starter_kit, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view, debug_heex_annotations: true, enable_expensive_runtime_checks: true

config :swoosh, :api_client, false
