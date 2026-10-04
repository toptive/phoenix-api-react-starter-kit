defmodule StarterKit.Repo.Migrations.AddApiTokenFields do
  use Ecto.Migration

  def change do
    alter table(:users_tokens) do
      add :expires_at, :utc_datetime
      add :sudo_until, :utc_datetime
      add :impersonator_id, references(:users, type: :binary_id, on_delete: :delete_all)
    end

    create index(:users_tokens, [:expires_at], where: "context = 'api'")
  end
end
