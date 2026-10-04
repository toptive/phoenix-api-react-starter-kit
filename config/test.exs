import Config

config :bcrypt_elixir, :log_rounds, 1

# One test database per checkout: worktrees running `mix test` at once must not share data.
checkout = :crypto.hash(:md5, File.cwd!()) |> Base.encode16(case: :lower) |> binary_part(0, 8)

config :starter_kit, StarterKit.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "starter_kit_test_#{checkout}#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  # Other worktrees share the machine: slow queries must not fail tests, and a small pool
  # keeps parallel lanes under Postgres max_connections (100). Raise POOL_SIZE when alone.
  timeout: 60_000,
  queue_target: 5_000,
  queue_interval: 20_000,
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

secret_key_base = "V6I7cJ+2c3sD2sLq3Qd8Pp0JmI0m9cZ3n5Qq9w5+Q5dQ0bSx7pWz3o3k6q9x2rT1"

# Signed tokens outside the web layer (Notifications: unsubscribe links).
config :starter_kit, :secret_key_base, secret_key_base

config :starter_kit, StarterKitWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: secret_key_base,
  server: false

config :starter_kit, Oban, testing: :inline
config :starter_kit, i18n_inline_reload: true
config :starter_kit, StarterKit.Mailer, adapter: Swoosh.Adapters.Test
config :starter_kit, StarterKit.Analytics, adapter: :test, raise_on_unknown: true

config :starter_kit, StarterKit.AI,
  http: StarterKit.AI.FakeHTTP,
  openrouter_api_key: "test",
  fal_key: "test",
  google_api_key: "test"

config :starter_kit, StarterKit.Uploads, bucket: "test-bucket"

# Billing on in test mode with fake keys; Stripe answers through Req.Test stubs.
# Flags: billing ON (below). Tests switch a flag with `with_flag/3` / `put_flag/2`
# (test/support/flag_helpers.ex), never with Application.put_env.
config :starter_kit, StarterKit.Flags, billing: true, test_overrides: true

config :starter_kit, StarterKit.Billing,
  mode: :test,
  secret_key: "sk_test_fake",
  webhook_secret: "whsec_test_fake",
  prices: %{"PRO_MONTHLY" => "price_test_monthly", "PRO_YEARLY" => "price_test_yearly"},
  req_options: [plug: {Req.Test, StarterKit.Billing.Stripe}]

# Turnstile off (the flag); tests turn it on with `put_flag(:turnstile, true)` and answer
# for Cloudflare through Req.Test stubs.
config :starter_kit, StarterKit.AbuseProtection,
  site_key: "public-site-key",
  secret_key: "fixture-secret",
  hostname: "app.example.com",
  req_options: [plug: {Req.Test, StarterKit.AbuseProtection}]

config :ex_aws,
  access_key_id: "test",
  secret_access_key: "test",
  region: "eu-central-1",
  s3: [scheme: "https://", host: "storage.example.com", region: "eu-central-1"]

config :swoosh, :api_client, false
config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
config :phoenix_live_view, enable_expensive_runtime_checks: true
config :phoenix, sort_verified_routes_query_params: true

# Every rendered Inertia page must match its `page` declaration: keys AND values.
config :typelizer, validate_inertia_props: :values
