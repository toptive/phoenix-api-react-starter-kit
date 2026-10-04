import Config

config :starter_kit, hsts: true, secure_cookies: true

# A flag ON with a wrong setup (billing: a missing key or price id, a key of the other
# mode…) stops the boot instead of failing at the first customer.
config :starter_kit, StarterKit.Flags, check_on_boot: true

config :swoosh, api_client: Swoosh.ApiClient.Req
config :swoosh, local: false

config :logger, level: :info

config :starter_kit, :raise_on_missing_authorization, false
