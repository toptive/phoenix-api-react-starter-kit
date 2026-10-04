defmodule StarterKitWeb.Endpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :starter_kit

  # Signed and encrypted cookie session.
  @session_options [
    store: :cookie,
    key: "_starter_kit_key",
    signing_salt: "56iPlTpx",
    encryption_salt: "xJ2kQd8r",
    same_site: "Lax",
    http_only: true
  ]

  # First plug on purpose: its before-send runs last (see the moduledoc).
  plug StarterKitWeb.Plugs.SecureCookies

  # Pre-launch indexing lock (SITE_INDEXING): before the error plug, so its header wins.
  plug StarterKitWeb.Plugs.SiteIndexing

  # Error responses (>= 400) are noindex and never cached, the last-resort pages too.
  plug StarterKitWeb.Plugs.ErrorResponses

  # One host (PHX_HOST in production): www., the server IP or an old domain get a 301.
  plug StarterKitWeb.Plugs.CanonicalHost

  # LiveView socket: only Oban Web and the dev LiveDashboard use it.
  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  # Vite output has content hashes in its file names: cache it forever.
  plug Plug.Static,
    at: "/assets",
    from: {:starter_kit, "priv/static/assets"},
    gzip: not code_reloading?,
    headers: %{"cache-control" => "public, max-age=31536000, immutable"}

  plug Plug.Static,
    at: "/",
    from: :starter_kit,
    gzip: not code_reloading?,
    only: StarterKitWeb.static_paths(),
    raise_on_missing_only: code_reloading?

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :starter_kit
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  # The visitor IP (rate limits, audit events, session devices). Forwarding headers count
  # only from TRUSTED_PROXY_CIDRS (kamal-proxy) and, through it, from Cloudflare.
  plug StarterKitWeb.Plugs.ClientIp

  plug StarterKitWeb.Plugs.Cors

  plug StarterKitWeb.Plugs.ApiTransport

  plug Sentry.PlugContext, body_scrubber: {__MODULE__, :scrub_body}
  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug StarterKitWeb.Router

  @doc false
  # Never send request bodies to Sentry.
  def scrub_body(_conn), do: %{}
end
