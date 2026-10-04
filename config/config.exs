# General configuration. Environment files below override it; secrets and
# deploy-specific values live in config/runtime.exs.
import Config

config :starter_kit,
  ecto_repos: [StarterKit.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  app_name: "StarterKit",
  theme_color: "#11694F",
  mail_from: {"StarterKit", "hello@example.com"},
  # A sender per locale, e.g. %{"es" => {"StarterKit", "hola@example.com"}} (Mailer.from/1).
  mail_from_by_locale: %{},
  # :multi — personal organization per user, invitations, switching
  # :single — one shared organization, no switching
  tenancy: :multi,
  # Who may create an account (SIGNUP_MODE): :open — anyone; :invite — only an email
  # with an open invitation; :closed — nobody (existing users still sign in).
  signup_mode: :open,
  ssr: false,
  ssr_pool_size: 1,
  google_auth: false,
  spa_origin: "http://localhost:5173",
  cors_origins: ["http://localhost:5173"]

# Used by `mix phx.gen.*` generators (--scope) — products get scoped contexts for free.
config :starter_kit, :scopes,
  user: [
    default: true,
    module: StarterKit.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: StarterKit.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

# The public site URL for emails (logo, footer link): jobs have no request URL.
config :starter_kit, :public_url, "http://localhost:4000"

config :starter_kit, :mail_brand, %{
  app_name: "StarterKit",
  accent: "#11694F",
  text: "#16222B",
  muted: "#5B6770"
}

config :starter_kit, StarterKitWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: StarterKitWeb.ErrorHTML, json: StarterKitWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: StarterKit.PubSub,
  live_view: [signing_salt: "A4iwPj55"]

config :starter_kit, StarterKit.Repo, migration_primary_key: [type: :binary_id]

# Oban: two queues only (default, marketing). Recurring jobs go in the Cron plugin.
config :starter_kit, Oban,
  engine: Oban.Engines.Basic,
  repo: StarterKit.Repo,
  queues: [default: 5, marketing: 2],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 7 * 24 * 60 * 60},
    Oban.Plugins.Lifeline,
    # Recurring work (perform/1 = one context call). A job whose feature is off returns
    # :ok at once; it never snoozes.
    {Oban.Plugins.Cron, crontab: [{"0 8 * * *", StarterKit.Billing.NoticeSweepWorker}]}
  ]

# AI-training crawlers allowed in robots.txt (search and AI-answer bots always are).
config :starter_kit, allowed_training_bots: ~w(GPTBot ClaudeBot Google-Extended CCBot)

config :inertia,
  endpoint: StarterKitWeb.Endpoint,
  default_version: "1",
  camelize_props: true,
  history: [encrypt: false],
  ssr: false,
  raise_on_ssr_failure: config_env() != :prod

config :starter_kit, StarterKit.Mailer, adapter: Swoosh.Adapters.Local

config :starter_kit, StarterKit.Analytics, adapter: :log, raise_on_unknown: true

config :starter_kit, StarterKit.AI,
  openrouter_model: "openai/gpt-4o-mini",
  gemini_model: "gemini-2.5-flash",
  app_name: "StarterKit"

# Feature flags (StarterKit.Flags): the defaults; config/runtime.exs reads the env vars.
config :starter_kit, StarterKit.Flags,
  billing: false,
  billing_renewal_notices: false,
  site_indexing: true,
  turnstile: false

# Paid plans (docs/BILLING.md). OFF until BILLING_ENABLED=true. The offers are the
# product's: amounts in cents, exactly the Stripe prices (the checkout refuses a mismatch).
config :starter_kit, StarterKit.Billing,
  mode: :test,
  currency: "usd",
  offers: [
    %{id: "pro_monthly", plan: "pro", interval: "month", amount_cents: 1_900},
    %{id: "pro_yearly", plan: "pro", interval: "year", amount_cents: 19_000}
  ],
  # Limits per plan (nil = unlimited). Every plan lists every key. Without a paid
  # subscription an organization has `default_plan`. Billing OFF = no limits at all.
  # Renewal notices (BILLING_RENEWAL_NOTICES=true): one email per period to the people who
  # manage billing, between `from` and `until` days before the renewal, for these intervals.
  renewal_notice_intervals: ["year"],
  renewal_notice_days: [from: 25, until: 15],
  default_plan: "free",
  plans: %{
    "free" => %{members: 3},
    "pro" => %{members: nil}
  }

config :ex_aws, http_client: ExAws.Request.Req, json_codec: Jason

config :ueberauth, Ueberauth,
  providers: [google: {Ueberauth.Strategy.Google, [default_scope: "email profile"]}]

config :sentry,
  dsn: nil,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  send_default_pii: false,
  integrations: [oban: [capture_errors: true]]

# Type contract: serializers, routes and Inertia page props → TypeScript
# (docs/TYPE_CONTRACT.md). `mix typelizer.gen` writes; `mix typelizer.check` gates.
config :typelizer,
  repo: StarterKit.Repo,
  router: StarterKitWeb.Router,
  output: [
    serializers: "frontend/src/api/generated/serializers",
    routes: "frontend/src/api/generated/routes",
    pages: nil
  ],
  # Oban Web: keep its entry page, skip its asset routes.
  routes: [exclude: ["/dev", "/live", ~r{^/admin/oban/}E], defaults: [:locale]]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
