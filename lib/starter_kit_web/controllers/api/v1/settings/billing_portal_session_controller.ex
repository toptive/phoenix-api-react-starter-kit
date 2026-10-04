defmodule StarterKitWeb.Api.V1.Settings.BillingPortalSessionController do
  @moduledoc "Creates a customer portal session, including while billing sales are off."
  use StarterKitWeb, :controller
  alias StarterKit.Billing
  alias StarterKitWeb.{ApiAuth, BillingResponses}

  def create(conn, _params) do
    conn = authorize!(conn, :manage_billing, scope(conn).organization)

    case Billing.create_portal_session(scope(conn), ApiAuth.spa_url("/settings/billing")) do
      {:ok, url} ->
        conn |> put_status(201) |> render_data({Serializers.RedirectUrlSerializer, %{url: url}})

      {:error, reason} ->
        BillingResponses.error(conn, reason)
    end
  end
end
