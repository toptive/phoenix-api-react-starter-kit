import Config

# Imported only by test.exs with E2E=1; never shares the request-test sandbox.
database = System.fetch_env!("E2E_PGDATABASE")
unless String.contains?(database, "e2e"), do: raise("E2E_PGDATABASE must contain e2e")
port = String.to_integer(System.fetch_env!("PORT"))

config :starter_kit, StarterKit.Repo,
  database: database,
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  pool: DBConnection.ConnectionPool

config :starter_kit, dev_routes: true

config :starter_kit, StarterKitWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: port],
  url: [host: "localhost", port: port],
  server: true,
  check_origin: false

config :starter_kit, StarterKit.Mailer, adapter: Swoosh.Adapters.Local

config :starter_kit, Oban,
  testing: :disabled,
  queues: [default: 2, marketing: 1],
  plugins: []

config :starter_kit, StarterKit.Flags,
  billing: System.get_env("E2E_BILLING") == "1",
  turnstile: false

config :starter_kit, StarterKit.AI,
  http: StarterKit.AI.HTTP,
  openrouter_api_key: nil,
  fal_key: nil,
  google_api_key: nil

# Fixture values only: this endpoint is the local Stripe stub, never Stripe itself.
config :starter_kit, StarterKit.Billing,
  req_options: [base_url: System.get_env("E2E_STRIPE_URL", "http://localhost:4200/v1/")]
