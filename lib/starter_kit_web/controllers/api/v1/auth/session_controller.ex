defmodule StarterKitWeb.Api.V1.Auth.SessionController do
  @moduledoc "Password sign-in and bearer session revocation."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts
  alias StarterKitWeb.ApiAuth

  plug StarterKitWeb.Plugs.RateLimit,
       [bucket: "api_session", limit: 10, period: 60_000] when action == :create

  def create(conn, params) do
    conn = skip_authorization(conn)

    ApiAuth.session_result(
      conn,
      Accounts.create_api_session(params, ApiAuth.device(conn)),
      "password"
    )
  end

  def delete(conn, _params) do
    conn = authorize!(conn, :delete, scope(conn).user)
    :ok = Accounts.delete_api_token(scope(conn), conn.assigns.api_token)
    render_data(conn, nil)
  end
end
