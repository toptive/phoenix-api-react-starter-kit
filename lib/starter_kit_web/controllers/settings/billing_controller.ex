defmodule StarterKitWeb.Settings.BillingController do
  @moduledoc """
  `GET /settings/billing`: the organization's plan, the paid offers (cards, one accept
  box, pay button) and the button to Stripe's portal whenever a subscription exists.

  404 while billing is off and the organization never subscribed. With sales off, an
  organization that has a subscription still sees it and can open the portal to cancel.
  Stripe sends people back here (`?checkout=done` after a payment).
  """
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.Billing

  page "settings/billing/show",
    props: [
      plan: :string,
      subscription: {:nullable, Serializers.SubscriptionSerializer},
      offers: {:list, Serializers.OfferSerializer},
      offer_revision: :string,
      sales: {:enum, [:open, :test, :closed]},
      can_manage: :boolean,
      from_checkout: :boolean
    ]

  def show(conn, params) do
    scope = scope(conn)
    conn = authorize!(conn, :show, scope.organization)
    subscription = Billing.current_subscription(scope)

    if Billing.enabled?() or subscription do
      render_inertia(conn, "settings/billing/show", %{
        plan: Billing.plan(scope),
        subscription: subscription && Serializers.SubscriptionSerializer.serialize(subscription),
        offers: Serializers.OfferSerializer.serialize_many(Billing.list_offers()),
        offer_revision: Billing.offer_revision(),
        sales: Billing.sales(scope.user),
        can_manage: can?(conn, :manage_billing, scope.organization),
        from_checkout: params["checkout"] == "done"
      })
    else
      conn |> put_status(404) |> put_view(StarterKitWeb.ErrorHTML) |> render(:"404")
    end
  end
end
