defmodule StarterKitWeb.Admin.LegalPublicationController do
  @moduledoc "Publishing a version = creating its publication."
  use StarterKitWeb, :controller

  alias StarterKit.Legal
  alias StarterKit.Legal.LegalDocument

  def create(conn, %{"legal_document_slug" => slug, "version_number" => number}) do
    conn = authorize!(conn, :update, LegalDocument)
    document = Legal.get_document!(scope(conn), slug)
    version = Legal.get_version!(document, number)
    {:ok, _} = Legal.publish_version(scope(conn), document, version)

    conn
    |> put_flash_t(:info, "flash.legal.published")
    |> redirect(to: ~p"/admin/legal-documents/#{slug}")
  end
end
