defmodule StarterKitWeb.Api.V1.Admin.LegalDocumentVersionController do
  @moduledoc "Superadmin legal document version API."
  use StarterKitWeb, :controller
  alias StarterKit.Legal
  alias StarterKit.Legal.LegalDocument
  alias StarterKitWeb.ApiAuth

  def create(conn, %{"slug" => slug} = params) do
    conn = authorize!(conn, :create, LegalDocument)

    case Legal.create_document_version(
           scope(conn),
           slug,
           Map.take(params, ["titles", "bodies", "note", "publish"])
         ) do
      {:ok, version} ->
        conn
        |> put_status(201)
        |> render_data({Serializers.LegalDocumentVersionSerializer, version})

      {:error, reason} ->
        ApiAuth.error(conn, reason)
    end
  end
end
