defmodule StarterKitWeb.Api.V1.EmailSubscriptionController do
  @moduledoc "Reads optional email preferences behind the signed unsubscribe token."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts
  alias StarterKitWeb.ApiAuth

  def show(conn, %{"token" => token}) do
    conn = skip_authorization(conn)

    case Accounts.email_subscription(token) do
      {:ok, subscription} ->
        render_data(conn, {Serializers.EmailSubscriptionSerializer, subscription})

      {:error, reason} ->
        ApiAuth.error(conn, reason)
    end
  end
end
