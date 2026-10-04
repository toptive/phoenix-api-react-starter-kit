defmodule StarterKitWeb.Api.V1.Admin.LegalPublicationController do
  @moduledoc "Superadmin legal publication API."
  use StarterKitWeb, :controller
  alias StarterKit.Legal
  alias StarterKit.Legal.LegalDocument
  alias StarterKitWeb.ApiAuth

  def create(conn, %{"slug" => slug, "number" => number}) do
    conn = authorize!(conn, :update, LegalDocument)

    case Legal.publish_document_version(scope(conn), slug, number) do
      {:ok, document} ->
        conn |> put_status(201) |> render_data({Serializers.LegalDocumentSerializer, document})

      {:error, reason} ->
        ApiAuth.error(conn, reason)
    end
  end
end
