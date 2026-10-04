defmodule StarterKitWeb.Api.V1.Auth.ImpersonationController do
  @moduledoc "Returns to the administrator's preserved session."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts
  alias StarterKitWeb.ApiAuth

  def delete(conn, _params) do
    conn = authorize!(conn, :show, scope(conn).user)

    case Accounts.stop_api_impersonation(scope(conn), conn.assigns.api_token) do
      {:ok, _} -> send_resp(conn, 204, "")
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end
end
