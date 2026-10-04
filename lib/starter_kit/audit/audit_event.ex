defmodule StarterKit.Audit.AuditEvent do
  @moduledoc "One append-only audit row (the database rejects UPDATE and DELETE)."

  use StarterKit.Schema, policy: StarterKit.Audit.AuditEventPolicy

  schema "audit_events" do
    field :action, :string
    field :actor_id, :binary_id
    field :impersonator_id, :binary_id
    field :organization_id, :binary_id
    field :subject_type, :string
    field :subject_id, :binary_id
    field :metadata, :map, default: %{}
    field :ip_address, :string
    field :actor_email, :string, virtual: true

    timestamps(updated_at: false)
  end
end
