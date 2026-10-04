defmodule StarterKit.Repo.Migrations.CreateBillingEvents do
  use Ecto.Migration

  # The inbox of verified Stripe webhooks. Only ids are stored (no payload, no customer
  # data); the unique (livemode, stripe_event_id) makes a repeated delivery a no-op.
  def change do
    create table(:billing_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :livemode, :boolean, null: false
      add :stripe_event_id, :string, null: false
      add :type, :string, null: false
      add :stripe_subscription_id, :string
      add :organization_id, :binary_id
      add :processed_at, :utc_datetime
      add :outcome, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:billing_events, [:livemode, :stripe_event_id])
  end
end
