defmodule StarterKitWeb.Api.V1.Settings.SessionController do
  @moduledoc "Account session settings through the JSON API."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts
  alias StarterKitWeb.ApiAuth

  def index(conn, _params) do
    conn = authorize!(conn, :show, scope(conn).user)
    sessions = Accounts.list_sessions(scope(conn), conn.assigns.api_token.id)
    render_collection(conn, sessions, Serializers.SessionSerializer, %{})
  end

  def delete(conn, %{"id" => id}) do
    conn = authorize!(conn, :update, scope(conn).user)

    case Accounts.revoke_session(scope(conn), id) do
      {:ok, _} -> send_resp(conn, 204, "")
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end
end
