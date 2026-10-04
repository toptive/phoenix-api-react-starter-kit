defmodule StarterKitWeb.Plugs.RateLimit do
  @moduledoc """
  Per-IP rate limit for unauthenticated endpoints that do work.

      plug StarterKitWeb.Plugs.RateLimit, [bucket: "session", limit: 10, period: :timer.minutes(1)] when action in [:create]

  Over the limit: 429 with the JSON error envelope (`/api`, `/webhooks`, or `format: :json` for a
  session-less route) or a translated flash and a redirect back (Inertia pages). Limits:
  docs/SECURITY.md.
  """

  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller

  alias StarterKitWeb.{RateLimit, Responses}

  @impl true
  def init(opts), do: Map.new(opts)

  @impl true
  def call(conn, %{bucket: bucket, limit: limit, period: period} = opts) do
    key = "#{bucket}:#{conn.remote_ip |> :inet.ntoa() |> to_string()}"

    case RateLimit.hit(key, period, limit) do
      {:allow, _count} ->
        conn

      {:deny, retry_after} ->
        conn = put_resp_header(conn, "retry-after", to_string(div(retry_after, 1000) + 1))

        if opts[:format] == :json or json?(conn) do
          conn |> Responses.render_error(429, :rate_limited) |> halt()
        else
          conn
          |> Responses.put_flash_t(:error, "errors.api.too_many_requests")
          |> put_status(303)
          |> redirect(to: back_path(conn))
          |> halt()
        end
    end
  end

  defp json?(conn), do: String.starts_with?(conn.request_path, ["/api/", "/webhooks/"])

  defp back_path(conn) do
    with [referer] <- get_req_header(conn, "referer"),
         %URI{path: path} when is_binary(path) <- URI.parse(referer) do
      path
    else
      _ -> "/"
    end
  end
end
