defmodule StarterKitWeb.Plugs.CanonicalHost do
  @moduledoc """
  One host for the whole site: a request to any other host (`www.`, the server IP, an old
  domain) gets a permanent redirect to the endpoint URL with the same path and query.
  GET and HEAD answer 301; other methods answer 308, so a form or webhook keeps its method.

  On only when `config :starter_kit, :canonical_host` is set (production: `PHX_HOST`).
  `/health` is never redirected: kamal-proxy checks it on the container address.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{request_path: "/health"} = conn, _opts), do: conn

  def call(conn, _opts) do
    case Application.get_env(:starter_kit, :canonical_host) do
      nil -> conn
      host when host == conn.host -> conn
      _other -> redirect(conn)
    end
  end

  defp redirect(conn) do
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string
    status = if conn.method in ~w(GET HEAD), do: 301, else: 308

    conn
    |> put_resp_header("location", StarterKitWeb.Endpoint.url() <> conn.request_path <> query)
    |> send_resp(status, "")
    |> halt()
  end
end
