defmodule StarterKitWeb.Api.V1.Auth.ConfirmationController do
  @moduledoc "Confirms the email behind a single-use magic token."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts
  alias StarterKitWeb.ApiAuth
  plug StarterKitWeb.Plugs.RateLimit, bucket: "api_confirmation", limit: 10, period: 60_000

  def create(conn, %{"token" => token}) do
    conn = skip_authorization(conn)

    case Accounts.confirm_api_email(token) do
      {:ok, _user} -> render_data(conn, nil)
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end
end
