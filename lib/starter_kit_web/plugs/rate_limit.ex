defmodule StarterKitWeb.Plugs.RateLimit do
  @moduledoc """
  Per-IP rate limit for unauthenticated endpoints that do work.

      plug StarterKitWeb.Plugs.RateLimit, [bucket: "session", limit: 10, period: :timer.minutes(1)] when action in [:create]

  Over the limit: 429 with the JSON error envelope and Retry-After.
  See docs/SECURITY.md.
  """

  @behaviour Plug

  import Plug.Conn

  alias StarterKitWeb.{RateLimit, Responses}

  @impl true
  def init(opts), do: Map.new(opts)

  @impl true
  def call(conn, %{bucket: bucket, limit: limit, period: period} = opts) do
    identity =
      if opts[:by] == :user,
        do: conn.assigns.current_user.id,
        else: conn.remote_ip |> :inet.ntoa() |> to_string()

    key = "#{bucket}:#{identity}"

    case RateLimit.hit(key, period, limit) do
      {:allow, _count} ->
        conn

      {:deny, retry_after} ->
        conn = put_resp_header(conn, "retry-after", to_string(div(retry_after, 1000) + 1))

        conn
        |> Responses.render_error(429, :rate_limited, %{retry_after: div(retry_after, 1000) + 1})
        |> halt()
    end
  end
end
