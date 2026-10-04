defmodule StarterKitWeb.Api.V1.Settings.EmailController do
  @moduledoc "Account email settings through the JSON API."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts
  alias StarterKitWeb.ApiAuth
  import StarterKitWeb.Plugs.BearerAuth, only: [require_sudo: 2]

  plug :require_sudo

  def update(conn, params) do
    conn = authorize!(conn, :update, scope(conn).user)

    case Accounts.request_email_change(
           scope(conn),
           Map.take(params, ["email"]),
           &ApiAuth.spa_url("/settings/email-confirmations/#{&1}")
         ) do
      {:ok, user} ->
        conn |> put_status(202) |> render_data({Serializers.EmailChangeSerializer, user})

      {:error, reason} ->
        ApiAuth.error(conn, reason)
    end
  end
end
