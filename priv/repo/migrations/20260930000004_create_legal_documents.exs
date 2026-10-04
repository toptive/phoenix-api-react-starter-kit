defmodule StarterKit.Repo.Migrations.CreateLegalDocuments do
  use Ecto.Migration

  def change do
    create table(:legal_documents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :published_version_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    create unique_index(:legal_documents, [:slug])

    create table(:legal_document_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :legal_document_id,
          references(:legal_documents, type: :binary_id, on_delete: :delete_all),
          null: false

      add :number, :integer, null: false
      add :titles, :map, null: false, default: %{}
      add :bodies, :map, null: false, default: %{}
      add :note, :string
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :published_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:legal_document_versions, [:legal_document_id, :number])

    create table(:legal_acceptances, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :legal_document_version_id,
          references(:legal_document_versions, type: :binary_id, on_delete: :restrict),
          null: false

      add :ip_address, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:legal_acceptances, [:user_id, :legal_document_version_id])
  end
end
