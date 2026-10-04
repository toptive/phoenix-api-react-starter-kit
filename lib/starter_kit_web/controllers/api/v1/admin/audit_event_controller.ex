defmodule StarterKitWeb.Api.V1.Admin.AuditEventController do
  @moduledoc "Superadmin audit event API."
  use StarterKitWeb, :controller
  alias StarterKit.Audit
  alias StarterKit.Audit.AuditEvent

  def index(conn, params) do
    conn = authorize!(conn, :index, AuditEvent)
    page = Audit.list_events(scope(conn), params)

    render_collection(conn, page.entries, Serializers.AuditEventSerializer, %{
      pagination: Serializers.PaginationSerializer.serialize(page)
    })
  end
end
