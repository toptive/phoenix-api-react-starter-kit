defmodule StarterKitWeb.Api.V1.Settings.PasswordController do
  @moduledoc "Account password settings through the JSON API."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts
  alias StarterKitWeb.ApiAuth
  import StarterKitWeb.Plugs.BearerAuth, only: [require_sudo: 2]

  plug :require_sudo

  def update(conn, params) do
    conn = authorize!(conn, :update, scope(conn).user)

    case Accounts.update_api_password(
           scope(conn),
           Map.take(params, ["password", "password_confirmation"]),
           ApiAuth.device(conn)
         ) do
      {:ok, session} -> render_data(conn, {Serializers.AuthSessionSerializer, session})
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end
end
