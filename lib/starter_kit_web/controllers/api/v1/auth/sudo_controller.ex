defmodule StarterKitWeb.Api.V1.Auth.SudoController do
  @moduledoc "Refreshes the bearer token's sudo window with password verification."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts
  alias StarterKitWeb.ApiAuth
  plug StarterKitWeb.Plugs.RateLimit, bucket: "api_sudo", limit: 5, period: 60_000

  def create(conn, params) do
    conn = authorize!(conn, :update, scope(conn).user)

    case Accounts.elevate_api_token(scope(conn), conn.assigns.api_token, params) do
      {:ok, token} -> render_data(conn, {Serializers.SudoWindowSerializer, token})
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end
end
