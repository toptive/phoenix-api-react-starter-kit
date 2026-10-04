import Config

# Runtime configuration: read from the environment at boot (dev, test and releases).
# Production env vars are listed in config/deploy.yml and docs/DEPLOY.md.

if System.get_env("PHX_SERVER") do
  config :starter_kit, StarterKitWeb.Endpoint, server: true
end

# Blank values count as unset (a blank SENTRY_DSN once crashed a deploy elsewhere).
env = fn name ->
  case System.get_env(name) do
    nil -> nil
    value -> if String.trim(value) == "", do: nil, else: value
  end
end

spa_origin =
  env.("PUBLIC_URL") || env.("SPA_ORIGIN") || if(config_env() != :prod, do: "http://localhost:5173")

cors_origins = env.("CORS_ORIGINS") || if(config_env() != :prod, do: spa_origin)
if is_nil(spa_origin), do: raise("SPA_ORIGIN is required in production")
if is_nil(cors_origins), do: raise("CORS_ORIGINS is required in production")

config :starter_kit,
  spa_origin: spa_origin,
  public_url: env.("PUBLIC_URL") || spa_origin,
  api_origin: env.("API_URL") || env.("API_ORIGIN") || "http://localhost:#{env.("PORT") || "4000"}",
  native_scheme: env.("NATIVE_SCHEME") || "starterkit",
  cors_origins:
    Enum.uniq(
      (cors_origins |> String.split(",", trim: true) |> Enum.map(&String.trim/1)) ++
        ["capacitor://localhost", "ionic://localhost", "http://localhost"]
    )

# Local Stripe stubs are forbidden in releases, even when billing uses test keys.
if base = env.("STRIPE_API_BASE") do
  if config_env() == :prod, do: raise("STRIPE_API_BASE cannot be overridden in production")
  uri = URI.parse(base)

  unless uri.scheme in ["http", "https"] and is_binary(uri.host) and is_nil(uri.userinfo),
    do: raise("STRIPE_API_BASE must be an HTTP(S) URL without credentials")

  config :starter_kit, StarterKit.Billing,
    req_options: [base_url: base],
    test_api_origin: if(config_env() == :test, do: {uri.scheme, uri.host, uri.port})
end

# The Sentry library also reads SENTRY_DSN from the OS env by itself, and a blank exported
# value would still turn it on. Remove the variable so "blank" means "off" everywhere.
if is_nil(env.("SENTRY_DSN")), do: System.delete_env("SENTRY_DSN")

config :starter_kit, StarterKit.AI,
  openrouter_api_key: env.("OPENROUTER_API_KEY"),
  openrouter_model: env.("OPENROUTER_MODEL") || "openai/gpt-4o-mini",
  fal_key: env.("FAL_KEY"),
  google_api_key: env.("GOOGLE_API_KEY"),
  gemini_model: env.("GEMINI_MODEL") || "gemini-2.5-flash",
  app_name: env.("APP_NAME") || "StarterKit"

# Outside production (staging, previews, a dev box with a real mail key) set
# MAIL_ALLOWED_RECIPIENTS: mail goes only to these addresses (`*@domain` matches a whole
# domain); any other recipient is dropped and logged. Unset = everyone (production).
if allowed = env.("MAIL_ALLOWED_RECIPIENTS") do
  config :starter_kit,
    mail_allowed_recipients:
      allowed |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
end

# Who may create an account (StarterKit.Accounts.signup_mode/0). A typo stops the boot
# instead of opening sign-up by accident.
if mode = env.("SIGNUP_MODE") do
  modes = %{"open" => :open, "invite" => :invite, "closed" => :closed}

  config :starter_kit,
    signup_mode:
      Map.get(modes, mode) ||
        raise("SIGNUP_MODE must be open, invite or closed, got: #{inspect(mode)}")
end

# Feature flags (StarterKit.Flags). Search engines may index the site: production starts
# locked ("0") until launch.
config :starter_kit, StarterKit.Flags,
  site_indexing: (env.("SITE_INDEXING") || if(config_env() == :prod, do: "0", else: "1")) == "1"

if config_env() != :test do
  # Proxies whose X-Forwarded-For we believe (StarterKitWeb.Plugs.ClientIp). Behind
  # kamal-proxy: the `kamal` Docker network (docker network inspect kamal). Empty = none.
  config :starter_kit,
    trusted_proxy_cidrs:
      (env.("TRUSTED_PROXY_CIDRS") || "")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

  # Billing (docs/BILLING.md): one mode per deployment. The keys and price ids of that
  # mode only: STRIPE_TEST_* or STRIPE_LIVE_*.
  billing_mode = if env.("BILLING_MODE") == "live", do: "LIVE", else: "TEST"
  price_prefix = "STRIPE_#{billing_mode}_PRICE_"

  config :starter_kit, StarterKit.Flags,
    billing: env.("BILLING_ENABLED") == "true",
    billing_renewal_notices: env.("BILLING_RENEWAL_NOTICES") == "true",
    turnstile: env.("TURNSTILE_REQUIRED") == "true"

  # Cloudflare Turnstile (StarterKit.AbuseProtection, docs/AUTH.md). The hostname the
  # widget runs on must match Cloudflare's answer.
  config :starter_kit, StarterKit.AbuseProtection,
    site_key: env.("TURNSTILE_SITE_KEY") && String.trim(env.("TURNSTILE_SITE_KEY")),
    secret_key: env.("TURNSTILE_SECRET_KEY") && String.trim(env.("TURNSTILE_SECRET_KEY")),
    hostname: env.("TURNSTILE_HOSTNAME") || env.("PHX_HOST") || "localhost"

  config :starter_kit, StarterKit.Billing,
    mode: if(billing_mode == "LIVE", do: :live, else: :test),
    secret_key: env.("STRIPE_#{billing_mode}_SECRET_KEY"),
    webhook_secret: env.("STRIPE_#{billing_mode}_WEBHOOK_SECRET"),
    test_operator_user_ids:
      (env.("BILLING_TEST_OPERATOR_USER_IDS") || "")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1),
    prices:
      for(
        {name, value} <- System.get_env(),
        String.starts_with?(name, price_prefix) and String.trim(value) != "",
        into: %{},
        do: {String.replace_prefix(name, price_prefix, ""), String.trim(value)}
      )

  if env.("GOOGLE_CLIENT_ID") && env.("GOOGLE_CLIENT_SECRET") do
    config :starter_kit, google_auth: true

    config :ueberauth, Ueberauth.Strategy.Google.OAuth,
      client_id: env.("GOOGLE_CLIENT_ID"),
      client_secret: env.("GOOGLE_CLIENT_SECRET")
  end

  if bucket = env.("S3_BUCKET") do
    endpoint = URI.parse(env.("S3_ENDPOINT") || "https://s3.amazonaws.com")

    config :starter_kit, StarterKit.Uploads, bucket: bucket
    config :starter_kit, :csp_connect_src, ["#{endpoint.scheme}://#{endpoint.host}"]

    config :ex_aws,
      access_key_id: env.("S3_ACCESS_KEY_ID"),
      secret_access_key: env.("S3_SECRET_ACCESS_KEY"),
      region: env.("S3_REGION") || "us-east-1",
      s3: [
        scheme: "#{endpoint.scheme}://",
        host: endpoint.host,
        port: endpoint.port,
        region: env.("S3_REGION") || "us-east-1"
      ]
  end

  # The PostHog region is the project's: https://us.i.posthog.com or https://eu.i.posthog.com.
  if posthog = env.("POSTHOG_API_KEY") do
    config :starter_kit, StarterKit.Analytics,
      adapter: :posthog,
      posthog_api_key: posthog,
      posthog_host:
        env.("POSTHOG_HOST") ||
          raise("POSTHOG_HOST is required with POSTHOG_API_KEY (US or EU host)"),
      raise_on_unknown: config_env() == :dev
  end
end

if config_env() == :prod do
  database_url =
    env.("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :starter_kit, StarterKit.Repo,
    url: database_url,
    pool_size: String.to_integer(env.("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    env.("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # Signed tokens outside the web layer (Notifications: unsubscribe links).
  config :starter_kit, :secret_key_base, secret_key_base

  host = env.("PHX_HOST") || "example.com"

  config :starter_kit, :public_url, env.("PUBLIC_URL") || spa_origin
  config :starter_kit, :api_origin, env.("API_URL") || env.("API_ORIGIN") || "https://#{host}"

  # Plugs.CanonicalHost: every other host gets a 301 to this one.
  config :starter_kit, :canonical_host, host

  config :starter_kit, :dns_cluster_query, env.("DNS_CLUSTER_QUERY")

  # Where billing emails send people to manage their plan (jobs have no request URL).
  config :starter_kit, StarterKit.Billing,
    manage_url: String.trim_trailing(env.("PUBLIC_URL") || spa_origin, "/") <> "/settings/billing"

  config :starter_kit, StarterKitWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    check_origin: ["https://#{host}", "https://www.#{host}"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: String.to_integer(env.("PORT") || "4000")],
    secret_key_base: secret_key_base

  config :starter_kit,
    app_name: env.("APP_NAME") || "StarterKit"

  config :starter_kit, Oban,
    queues: [
      default: String.to_integer(env.("OBAN_DEFAULT_CONCURRENCY") || "5"),
      marketing: String.to_integer(env.("OBAN_MARKETING_CONCURRENCY") || "2")
    ]

  # Postmark message streams: access + transactional mail, and optional (broadcast) mail.
  config :starter_kit, :postmark_streams, %{
    transactional: env.("POSTMARK_TRANSACTIONAL_STREAM") || "outbound",
    broadcast: env.("POSTMARK_BROADCAST_STREAM") || "broadcast"
  }

  if postmark = env.("POSTMARK_API_KEY") do
    config :starter_kit, StarterKit.Mailer, adapter: Swoosh.Adapters.Postmark, api_key: postmark
  else
    config :starter_kit, StarterKit.Mailer, adapter: Swoosh.Adapters.Logger, level: :info
  end

  {default_name, default_from} =
    {env.("MAIL_FROM_NAME") || "StarterKit", env.("MAIL_FROM") || "hello@example.com"}

  if env.("MAIL_FROM") do
    config :starter_kit, mail_from: {default_name, default_from}
  end

  # A sender per locale: MAIL_FROM_ES=hola@… and/or MAIL_FROM_NAME_ES="Equipo …"
  # (ZH_HK for zh-HK). A locale without them uses MAIL_FROM / MAIL_FROM_NAME.
  mail_locales =
    for {"MAIL_FROM_" <> suffix, _} <- System.get_env(), suffix != "NAME", uniq: true do
      String.replace_prefix(suffix, "NAME_", "")
    end

  config :starter_kit,
    mail_from_by_locale:
      Map.new(mail_locales, fn suffix ->
        {suffix |> String.downcase() |> String.replace("_", "-"),
         {env.("MAIL_FROM_NAME_" <> suffix) || default_name,
          env.("MAIL_FROM_" <> suffix) || default_from}}
      end)

  if dsn = env.("SENTRY_DSN") do
    config :sentry,
      dsn: dsn,
      environment_name: env.("SENTRY_ENV") || "production",
      release: env.("KAMAL_VERSION"),
      before_send: {StarterKit.Monitoring, :scrub}

    config :logger, :default_handler, level: :info
  end
end
