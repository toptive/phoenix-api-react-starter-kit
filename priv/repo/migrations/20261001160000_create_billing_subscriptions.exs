defmodule StarterKit.Repo.Migrations.CreateBillingSubscriptions do
  use Ecto.Migration

  # One row per organization and Stripe mode: the organization's current subscription,
  # as last read from Stripe. Billing records are kept: an organization with one cannot
  # be deleted by accident (on_delete: :restrict).
  def change do
    create table(:billing_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :livemode, :boolean, null: false
      add :stripe_customer_id, :string, null: false
      add :stripe_subscription_id, :string, null: false
      add :offer_id, :string
      add :plan, :string, null: false
      add :status, :string, null: false
      add :current_period_end, :utc_datetime
      add :cancel_at_period_end, :boolean, null: false, default: false
      add :paused, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:billing_subscriptions, [:organization_id, :livemode])
    create unique_index(:billing_subscriptions, [:livemode, :stripe_subscription_id])
  end
end
