defmodule StarterKitWeb.Settings.BillingPortalSessionController do
  @moduledoc """
  `POST /settings/billing/portal-session`: opens Stripe's customer portal (card,
  invoices, cancel) for the current organization's subscription (for an Inertia visit:
  409 with `x-inertia-location`). It works even when sales are off, so a customer can
  always cancel. A refusal comes back with a flash.
  """
  use StarterKitWeb, :controller

  alias StarterKit.Billing

  def create(conn, _params) do
    conn = authorize!(conn, :manage_billing, scope(conn).organization)

    case Billing.create_portal_session(scope(conn), url(~p"/settings/billing")) do
      {:ok, portal_url} ->
        redirect(conn, external: portal_url)

      {:error, :no_subscription} ->
        conn
        |> put_flash_t(:error, "billing.portal.no_subscription")
        |> redirect(to: ~p"/settings/billing")

      {:error, _reason} ->
        conn |> put_flash_t(:error, "billing.portal.failed") |> redirect(to: ~p"/settings/billing")
    end
  end
end
