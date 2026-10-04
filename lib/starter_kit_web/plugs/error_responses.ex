defmodule StarterKitWeb.Plugs.ErrorResponses do
  @moduledoc """
  Every error response (status 400 and above) is `noindex` and never cached: a 404 or a
  500 must not land in a search index or in a shared cache (a CDN in front of the app
  would otherwise keep serving a passing failure).

  It sits at the top of the endpoint, so it also covers the last-resort pages that
  Phoenix renders through `StarterKitWeb.ErrorHTML` (unmatched routes, crashes).
  """

  @behaviour Plug

  import Plug.Conn

  alias StarterKitWeb.Plugs.ApiLocale

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn =
      if String.starts_with?(conn.request_path, "/api/") do
        conn
        |> Phoenix.Controller.put_format("json")
        |> fetch_query_params()
        |> ApiLocale.call([])
      else
        conn
      end

    conn =
      if String.starts_with?(conn.request_path, "/api/"),
        do: put_resp_header(conn, "cache-control", "private, no-store"),
        else: conn

    register_before_send(conn, &mark_error/1)
  end

  defp mark_error(%Plug.Conn{request_path: "/health"} = conn),
    do: put_resp_header(conn, "cache-control", "no-store")

  defp mark_error(%Plug.Conn{status: status} = conn) when is_integer(status) and status >= 400 do
    conn
    |> put_resp_header("x-robots-tag", "noindex")
    |> put_resp_header("cache-control", "private, no-store")
  end

  defp mark_error(conn), do: conn
end
