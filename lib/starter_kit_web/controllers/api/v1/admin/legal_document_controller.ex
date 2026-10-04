defmodule StarterKitWeb.Api.V1.Admin.LegalDocumentController do
  @moduledoc "Superadmin legal document API."
  use StarterKitWeb, :controller
  alias StarterKit.Legal
  alias StarterKit.Legal.LegalDocument

  def index(conn, _params) do
    conn = authorize!(conn, :index, LegalDocument)

    render_collection(
      conn,
      Legal.list_documents(scope(conn)),
      Serializers.LegalDocumentSerializer,
      %{}
    )
  end

  def show(conn, %{"slug" => slug}) do
    conn = authorize!(conn, :edit, LegalDocument)
    render_data(conn, {Serializers.LegalDocumentSerializer, Legal.get_document!(scope(conn), slug)})
  end
end
