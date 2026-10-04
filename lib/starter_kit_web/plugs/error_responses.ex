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

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts), do: register_before_send(conn, &mark_error/1)

  defp mark_error(%Plug.Conn{status: status} = conn) when is_integer(status) and status >= 400 do
    conn
    |> put_resp_header("x-robots-tag", "noindex")
    |> put_resp_header("cache-control", "private, no-store")
  end

  defp mark_error(conn), do: conn
end
