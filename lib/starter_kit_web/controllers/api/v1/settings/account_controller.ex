defmodule StarterKitWeb.Api.V1.Settings.AccountController do
  @moduledoc "Account deletion and its ownership or subscription blockers."
  use StarterKitWeb, :controller
  import StarterKitWeb.Plugs.BearerAuth, only: [require_sudo: 2]
  alias StarterKit.Privacy
  alias StarterKitWeb.ApiAuth

  plug :require_sudo

  plug StarterKitWeb.Plugs.RateLimit,
       [bucket: "api_account_deletion", limit: 5, period: 60_000] when action == :delete

  def show(conn, _params) do
    conn = authorize!(conn, :show, scope(conn).user)

    render_data(
      conn,
      {Serializers.AccountDeletionSerializer, Privacy.account_deletion(scope(conn))}
    )
  end

  def delete(conn, _params) do
    conn = authorize!(conn, :delete, scope(conn).user)

    case Privacy.delete_account(scope(conn)) do
      {:ok, _} -> send_resp(conn, 204, "")
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end
end
