defmodule StarterKitWeb.Plugs.XsrfHeader do
  @moduledoc """
  The Inertia client (axios) sends the CSRF token as `X-XSRF-TOKEN`, read from the
  `XSRF-TOKEN` cookie that `Inertia.Plug` sets. `Plug.CSRFProtection` only reads
  `X-CSRF-Token`. This plug copies the first into the second, before
  `protect_from_forgery`. The token is the same signed, session-bound value either way.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case {get_req_header(conn, "x-csrf-token"), get_req_header(conn, "x-xsrf-token")} do
      {[], [token | _]} -> put_req_header(conn, "x-csrf-token", token)
      _ -> conn
    end
  end
end
