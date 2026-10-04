defmodule StarterKit.Repo.Migrations.CreateTranslations do
  use Ecto.Migration

  def change do
    create table(:translations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :locale, :string, null: false
      add :value, :text, null: false, default: ""
      # true once an admin edits the row: the CSV sync never overwrites it again
      add :edited, :boolean, null: false, default: false
      add :edited_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:translations, [:key, :locale])
    create index(:translations, [:locale])
  end
end
