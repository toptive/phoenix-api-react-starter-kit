defmodule StarterKitWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Security headers and a Content-Security-Policy with a per-request nonce
  (`@csp_nonce`, used by the inline appearance script and Oban Web).
  In dev the Vite dev server (and its websocket) is allowed too; with Turnstile ON,
  `challenges.cloudflare.com` (script, iframe).
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    nonce = 18 |> :crypto.strong_rand_bytes() |> Base.encode64(padding: false)
    vite = Application.get_env(:starter_kit, :vite_dev_server)
    vite_ws = vite && String.replace(vite, ~r/^http/, "ws")
    extra_connect = Application.get_env(:starter_kit, :csp_connect_src, [])
    # Turnstile's script and challenge iframe, only while the flag is ON.
    turnstile = if StarterKit.AbuseProtection.required?(), do: "https://challenges.cloudflare.com"

    csp =
      [
        "default-src 'self'",
        "script-src 'self' 'nonce-#{nonce}' #{vite} #{turnstile}",
        "style-src 'self' 'unsafe-inline' #{vite}",
        "img-src 'self' data: blob: https:",
        "font-src 'self' data: #{vite}",
        "connect-src 'self' #{vite} #{vite_ws} #{Enum.join(extra_connect, " ")} #{turnstile}",
        "frame-src 'self' #{turnstile}",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "form-action 'self' https://accounts.google.com",
        "object-src 'none'"
      ]
      |> Enum.map_join("; ", &(&1 |> String.replace(~r/\s+/, " ") |> String.trim()))

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", csp)
    |> put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
    |> put_resp_header("permissions-policy", "camera=(), microphone=(), geolocation=()")
    |> maybe_hsts()
  end

  # TLS ends at kamal-proxy; tell browsers to stay on HTTPS (production only).
  defp maybe_hsts(conn) do
    if Application.get_env(:starter_kit, :hsts, false),
      do: put_resp_header(conn, "strict-transport-security", "max-age=31536000; includeSubDomains"),
      else: conn
  end
end
