defmodule StarterKitWeb.Api.V1.Auth.SessionController do
  @moduledoc "Password sign-in and bearer session revocation."
  use StarterKitWeb, :controller
  alias StarterKit.{Accounts, Organizations}
  alias StarterKitWeb.ApiAuth

  plug StarterKitWeb.Plugs.RateLimit,
       [bucket: "api_session", limit: 10, period: 60_000] when action == :create

  def create(conn, params) do
    conn = skip_authorization(conn)

    ApiAuth.session_result(
      conn,
      Organizations.create_password_session(params, ApiAuth.device(conn), conn.assigns.api_token),
      "password"
    )
  end

  def delete(conn, _params) do
    conn = authorize!(conn, :delete, scope(conn).user)
    :ok = Accounts.delete_api_token(scope(conn), conn.assigns.api_token)
    send_resp(conn, 204, "")
  end
end
