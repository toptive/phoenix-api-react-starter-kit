defmodule StarterKitWeb.Admin.LegalDocumentVersionController do
  @moduledoc "Save a new version (optionally publishing it at once)."
  use StarterKitWeb, :controller

  alias StarterKit.Legal
  alias StarterKit.Legal.LegalDocument

  def create(conn, %{"legal_document_slug" => slug, "version" => params}) do
    conn = authorize!(conn, :create, LegalDocument)
    document = Legal.get_document!(scope(conn), slug)
    publish? = params["publish"] in [true, "true"]

    case Legal.create_version(scope(conn), document, params, publish: publish?) do
      {:ok, _} ->
        put_flash_t(
          conn,
          :info,
          if(publish?, do: "flash.legal.published", else: "flash.legal.saved")
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        assign_changeset_errors(conn, changeset)
    end
    |> redirect(to: ~p"/admin/legal-documents/#{slug}")
  end
end
