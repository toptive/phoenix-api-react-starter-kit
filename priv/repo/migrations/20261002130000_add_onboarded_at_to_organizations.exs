defmodule StarterKit.Repo.Migrations.AddOnboardedAtToOrganizations do
  use Ecto.Migration

  # Nil until a manager finishes (or skips) onboarding. Organizations that exist before
  # this migration count as onboarded, so nobody is sent back to the first-run steps.
  def up do
    alter table(:organizations) do
      add :onboarded_at, :utc_datetime
    end

    execute "UPDATE organizations SET onboarded_at = inserted_at"
  end

  def down do
    alter table(:organizations) do
      remove :onboarded_at
    end
  end
end
