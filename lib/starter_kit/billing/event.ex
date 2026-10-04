defmodule StarterKit.Billing.Event do
  @moduledoc false
  # A verified Stripe webhook in the inbox (only ids: no payload, no customer data).
  # `organization_id` is the hint from the event's metadata, checked again against the
  # subscription fetched from Stripe. Not a tenant table: an event arrives before we
  # know (or trust) its organization. `outcome` says what processing did.

  use StarterKit.Schema

  schema "billing_events" do
    field :livemode, :boolean
    field :stripe_event_id, :string
    field :type, :string
    field :stripe_subscription_id, :string
    field :organization_id, :binary_id
    field :processed_at, :utc_datetime
    field :outcome, :string

    timestamps(updated_at: false)
  end
end
