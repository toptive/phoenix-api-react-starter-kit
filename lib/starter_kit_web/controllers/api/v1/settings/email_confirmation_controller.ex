defmodule StarterKitWeb.Api.V1.Settings.EmailConfirmationController do
  @moduledoc "Account email confirmation settings through the JSON API."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts
  alias StarterKitWeb.ApiAuth

  plug StarterKitWeb.Plugs.RateLimit,
       [bucket: "api_email_confirmation", limit: 10, period: 60_000] when action == :create

  def show(conn, %{"token" => token}) do
    conn = authorize!(conn, :update, scope(conn).user)

    case Accounts.peek_email_change(scope(conn), token) do
      {:ok, change} -> render_data(conn, {Serializers.EmailChangeSerializer, change})
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end

  def create(conn, params) do
    conn = authorize!(conn, :update, scope(conn).user)

    case Accounts.update_user_email(scope(conn).user, params["token"]) do
      {:ok, user} -> render_data(conn, {Serializers.UserSerializer, user})
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end
end
