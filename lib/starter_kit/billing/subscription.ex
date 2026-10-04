defmodule StarterKit.Billing.Subscription do
  @moduledoc """
  An organization's Stripe subscription, one row per organization and mode (`livemode`).
  Written only from Stripe's own answer (reconciliation), never from a browser.

  `status` is Stripe's: `active`, `trialing` and `past_due` (Stripe is still retrying
  the payment) give the paid plan until `current_period_end`; `canceled`, `unpaid`,
  `incomplete`, `incomplete_expired` and `paused` do not. A paused collection
  (`paused: true`) does not either.
  """

  use StarterKit.Schema, policy: StarterKit.Billing.SubscriptionPolicy, tenant: true

  @paid_statuses ~w(active trialing past_due)

  schema "billing_subscriptions" do
    field :livemode, :boolean
    field :stripe_customer_id, :string
    field :stripe_subscription_id, :string
    field :offer_id, :string
    field :plan, :string
    field :status, :string
    field :current_period_end, :utc_datetime
    field :cancel_at_period_end, :boolean, default: false
    field :paused, :boolean, default: false
    field :renewal_notice_sent_for, :utc_datetime

    belongs_to :organization, StarterKit.Organizations.Organization
    timestamps()
  end

  @doc "True when this subscription gives its plan at `now`."
  def paid?(%__MODULE__{} = sub, now \\ DateTime.utc_now()) do
    sub.status in @paid_statuses and not sub.paused and
      not is_nil(sub.current_period_end) and DateTime.after?(sub.current_period_end, now)
  end
end
