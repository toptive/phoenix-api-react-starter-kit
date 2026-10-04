defmodule StarterKitWeb.Admin.LegalDocumentController do
  @moduledoc "Terms, privacy and cookies: versions and the published one."
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.Legal
  alias StarterKit.Legal.LegalDocument

  page "admin/legal-documents/index",
    props: [documents: {:list, Serializers.LegalDocumentSerializer}]

  page "admin/legal-documents/show",
    props: [document: Serializers.LegalDocumentSerializer]

  def index(conn, _params) do
    conn = authorize!(conn, :index, LegalDocument)

    render_inertia(conn, "admin/legal-documents/index", %{
      documents:
        Serializers.LegalDocumentSerializer.serialize_many(Legal.list_documents(scope(conn)))
    })
  end

  def show(conn, %{"slug" => slug}) do
    conn = authorize!(conn, :edit, LegalDocument)
    document = Legal.get_document!(scope(conn), slug)

    render_inertia(conn, "admin/legal-documents/show", %{
      document: Serializers.LegalDocumentSerializer.serialize(document)
    })
  end
end
