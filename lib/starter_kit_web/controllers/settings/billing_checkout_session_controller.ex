defmodule StarterKitWeb.Settings.BillingCheckoutSessionController do
  @moduledoc """
  `POST /settings/billing/checkout-session`: starts a Stripe Checkout for the current
  organization and sends the browser to Stripe (for an Inertia visit: 409 with
  `x-inertia-location`). A refusal comes back with a flash. 404 while billing is off.

  Params: `checkout[offer_id]`, `checkout[offer_revision]`, `checkout[accepted]`.
  """
  use StarterKitWeb, :controller

  alias StarterKit.Billing

  plug :require_billing

  def create(conn, params) do
    conn = authorize!(conn, :manage_billing, scope(conn).organization)

    urls = %{
      success_url: url(~p"/settings/billing?checkout=done"),
      cancel_url: url(~p"/settings/billing")
    }

    case Billing.create_checkout_session(scope(conn), params["checkout"] || %{}, urls) do
      {:ok, checkout_url} ->
        redirect(conn, external: checkout_url)

      {:error, reason} ->
        conn |> put_flash_t(:error, flash_key(reason)) |> redirect(to: ~p"/settings/billing")
    end
  end

  defp flash_key(reason)
       when reason in [:offer_changed, :not_accepted, :test_mode, :already_subscribed],
       do: "billing.checkout.#{reason}"

  defp flash_key(:unknown_offer), do: "billing.checkout.offer_changed"
  defp flash_key(_reason), do: "billing.checkout.failed"

  defp require_billing(conn, _opts) do
    if Billing.enabled?() do
      conn
    else
      conn
      |> skip_authorization()
      |> put_status(404)
      |> put_view(StarterKitWeb.ErrorHTML)
      |> render(:"404")
      |> halt()
    end
  end
end
