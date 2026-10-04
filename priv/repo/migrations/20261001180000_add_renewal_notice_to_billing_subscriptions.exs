defmodule StarterKit.Repo.Migrations.AddRenewalNoticeToBillingSubscriptions do
  use Ecto.Migration

  # The period end a renewal notice was sent for: one notice per period, never two.
  def change do
    alter table(:billing_subscriptions) do
      add :renewal_notice_sent_for, :utc_datetime
    end
  end
end
