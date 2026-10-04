defmodule StarterKit.Repo.Migrations.CreateAuditEvents do
  use Ecto.Migration

  def change do
    create table(:audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :action, :string, null: false
      add :actor_id, :binary_id
      add :impersonator_id, :binary_id
      add :organization_id, :binary_id
      add :subject_type, :string
      add :subject_id, :binary_id
      add :metadata, :map, null: false, default: %{}
      add :ip_address, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:audit_events, [:actor_id])
    create index(:audit_events, [:organization_id])
    create index(:audit_events, [:subject_type, :subject_id])
    create index(:audit_events, [:inserted_at])

    # Append-only (SOC 2): the database refuses UPDATE and DELETE on audit_events.
    execute(
      """
      CREATE FUNCTION audit_events_append_only() RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'audit_events is append-only';
      END;
      $$ LANGUAGE plpgsql;
      """,
      "DROP FUNCTION audit_events_append_only();"
    )

    execute(
      """
      CREATE TRIGGER audit_events_no_change BEFORE UPDATE OR DELETE ON audit_events
      FOR EACH ROW EXECUTE FUNCTION audit_events_append_only();
      """,
      "DROP TRIGGER audit_events_no_change ON audit_events;"
    )

    create table(:impersonations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :admin_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :target_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :reason, :string, null: false
      add :ended_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:impersonations, [:admin_id])
  end
end
