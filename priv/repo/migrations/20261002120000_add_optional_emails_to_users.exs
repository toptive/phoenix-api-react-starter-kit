defmodule StarterKit.Repo.Migrations.AddOptionalEmailsToUsers do
  use Ecto.Migration

  # False after a one-click unsubscribe: no more optional (lifecycle, marketing) mail.
  def change do
    alter table(:users) do
      add :optional_emails, :boolean, null: false, default: true
    end
  end
end
