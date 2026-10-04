defmodule StarterKit.Repo.Migrations.CreateBearerSessions do
  use Ecto.Migration

  def up do
    create table(:sessions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :organization_id, references(:organizations, type: :uuid, on_delete: :nilify_all)
      add :impersonator_user_id, references(:users, type: :uuid, on_delete: :delete_all)
      add :impersonator_session_id, references(:sessions, type: :uuid, on_delete: :delete_all)
      add :impersonation_id, references(:impersonations, type: :uuid, on_delete: :nilify_all)
      add :authenticated_at, :timestamptz, null: false
      add :sudo_until, :timestamptz
      add :expires_at, :timestamptz, null: false
      add :last_used_at, :timestamptz
      add :revoked_at, :timestamptz
      add :user_agent, :text
      add :ip_address, :text
      timestamps(type: :timestamptz, updated_at: false)
    end

    create unique_index(:sessions, [:token_hash])
    create index(:sessions, [:user_id])
    create index(:sessions, [:impersonator_session_id])
    create index(:sessions, [:expires_at])

    # Prior sessions used a different digest and cannot authenticate under the contract.
    execute "DELETE FROM users_tokens WHERE context IN ('api', 'session', 'reset_password')"
    execute "UPDATE users_tokens SET context = 'magic_link' WHERE context = 'login'"

    execute "UPDATE users_tokens SET context = 'change_email:' || substring(context from 8) WHERE context LIKE 'change:%'"

    rename table(:users_tokens), to: table(:user_tokens)

    alter table(:user_tokens) do
      remove :expires_at
      remove :sudo_until
      remove :impersonator_id
      remove :authenticated_at
      remove :user_agent
      remove :ip_address
    end
  end

  def down do
    alter table(:user_tokens) do
      add :expires_at, :utc_datetime
      add :sudo_until, :utc_datetime
      add :authenticated_at, :utc_datetime
      add :user_agent, :string
      add :ip_address, :string
      add :impersonator_id, references(:users, type: :uuid, on_delete: :delete_all)
    end

    rename table(:user_tokens), to: table(:users_tokens)
    execute "UPDATE users_tokens SET context = 'login' WHERE context = 'magic_link'"

    execute "UPDATE users_tokens SET context = 'change:' || substring(context from 14) WHERE context LIKE 'change_email:%'"

    drop table(:sessions)
  end
end
