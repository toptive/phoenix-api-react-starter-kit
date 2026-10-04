defmodule StarterKit.Legal.LegalDocument do
  @moduledoc "Terms, privacy or cookies policy. The published version is what the public page shows."

  use StarterKit.Schema, policy: StarterKit.Legal.LegalDocumentPolicy

  @slugs ~w(terms privacy cookies)

  schema "legal_documents" do
    field :slug, :string
    belongs_to :published_version, StarterKit.Legal.LegalDocumentVersion
    has_many :versions, StarterKit.Legal.LegalDocumentVersion, preload_order: [desc: :number]

    timestamps()
  end

  def slugs, do: @slugs
end
