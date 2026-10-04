defmodule StarterKit.Repo.Migrations.KeepLegalAcceptances do
  use Ecto.Migration

  # A deleted account must not delete the proof that it accepted the terms: the row
  # stays, `user_id` becomes NULL, and a SHA-256 of the lower-case email still names
  # the person who accepted.
  def up do
    alter table(:legal_acceptances) do
      add :subject_email_hash, :string

      modify :user_id, references(:users, type: :binary_id, on_delete: :nilify_all),
        null: true,
        from: {references(:users, type: :binary_id, on_delete: :delete_all), null: false}
    end

    execute """
    UPDATE legal_acceptances AS a
    SET subject_email_hash = encode(sha256(convert_to(lower(u.email::text), 'UTF8')), 'hex')
    FROM users AS u
    WHERE u.id = a.user_id
    """
  end

  def down do
    execute "DELETE FROM legal_acceptances WHERE user_id IS NULL"

    alter table(:legal_acceptances) do
      remove :subject_email_hash

      modify :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false,
        from: {references(:users, type: :binary_id, on_delete: :nilify_all), null: true}
    end
  end
end
