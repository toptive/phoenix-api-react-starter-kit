defmodule StarterKitWeb.Plugs.RawBody do
  @moduledoc """
  `Plug.Parsers` body reader that keeps the raw bytes of webhook requests in
  `conn.assigns.raw_body`. Signed webhooks (Stripe) are verified on the exact bytes
  received; the parsed JSON cannot be re-encoded into them. Other paths are untouched.

      plug Plug.Parsers, …, body_reader: {StarterKitWeb.Plugs.RawBody, :read_body, []}
  """

  @prefix "/webhooks/"

  @doc false
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, body, keep(conn, body)}
      {:more, body, conn} -> {:more, body, keep(conn, body)}
      error -> error
    end
  end

  defp keep(%{request_path: @prefix <> _} = conn, body),
    do: Plug.Conn.assign(conn, :raw_body, (conn.assigns[:raw_body] || "") <> body)

  defp keep(conn, _body), do: conn
end
