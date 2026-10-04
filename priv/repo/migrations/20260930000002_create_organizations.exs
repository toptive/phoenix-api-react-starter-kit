defmodule StarterKit.Repo.Migrations.CreateOrganizations do
  use Ecto.Migration

  def change do
    create table(:organizations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :citext, null: false
      add :personal, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:organizations, [:slug])

    create table(:memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "member"
      add :access, :string, null: false, default: "full"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:memberships, [:organization_id, :user_id])
    create index(:memberships, [:user_id])

    create constraint(:memberships, :role_must_be_known,
             check: "role IN ('owner', 'admin', 'member')"
           )

    create constraint(:memberships, :access_must_be_known, check: "access IN ('full', 'viewer')")

    create table(:invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :invited_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :email, :citext, null: false
      add :role, :string, null: false, default: "member"
      add :access, :string, null: false, default: "full"
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:invitations, [:token_hash])
    create index(:invitations, [:organization_id])

    create unique_index(:invitations, [:organization_id, :email],
             where: "accepted_at IS NULL",
             name: :invitations_pending_email_index
           )
  end
end
