defmodule StarterKit.Legal.LegalAcceptance do
  @moduledoc """
  Proof that a user accepted a specific version (when, from which IP). It outlives the
  account: `user_id` becomes nil on deletion, and `subject_email_hash` (SHA-256 of the
  lower-case email) still names the person.
  """

  use StarterKit.Schema

  schema "legal_acceptances" do
    field :ip_address, :string
    field :user_id, :binary_id
    field :subject_email_hash, :string
    belongs_to :legal_document_version, StarterKit.Legal.LegalDocumentVersion

    timestamps(updated_at: false)
  end
end
