defmodule StarterKitWeb.Api.V1.DirectUploadController do
  @moduledoc "Signs a direct upload to object storage (see `StarterKit.Uploads`)."
  use StarterKitWeb, :controller

  alias StarterKit.Accounts.Scope
  alias StarterKit.Organizations.Organization
  alias StarterKit.Uploads

  plug StarterKitWeb.Plugs.RateLimit, bucket: "uploads", limit: 60, period: 60_000

  def create(conn, %{"direct_upload" => params}) do
    conn = authorize!(conn, :show, scope(conn).organization || Organization)

    case Uploads.presign(Scope.organization_id(scope(conn)), params) do
      {:ok, upload} ->
        render_data(conn, Serializers.DirectUploadSerializer.serialize(upload), status: 201)

      {:error, reason}
      when reason in [:content_type_not_allowed, :too_large, :invalid_size, :unknown_kind] ->
        render_error(conn, 422, reason)

      {:error, :not_configured} ->
        render_error(conn, 503, :uploads_not_configured)

      {:error, _} ->
        render_error(conn, 400, :bad_request)
    end
  end
end
