defmodule StarterKit.Repo.Migrations.IndexAuditSubject do
  use Ecto.Migration
  def change, do: create(index(:audit_events, [:subject_id]))
end
