defmodule StarterKitWeb.Plugs.SecureCookies do
  @moduledoc """
  Marks every response cookie `Secure` when `config :starter_kit, :secure_cookies` is true
  (production): jobs and dev-tool session cookies are never sent over plain HTTP.

  It is the FIRST plug in the endpoint: before-send callbacks run in reverse order, so
  this one runs last, after `Plug.Session` has written its cookies.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if Application.get_env(:starter_kit, :secure_cookies, false) do
      register_before_send(conn, fn conn ->
        %{
          conn
          | resp_cookies:
              Map.new(conn.resp_cookies, fn {k, v} -> {k, Map.put(v, :secure, true)} end)
        }
      end)
    else
      conn
    end
  end
end
