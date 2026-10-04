defmodule StarterKitWeb.Admin.AuditEventController do
  @moduledoc "The audit log (read only)."
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.Audit
  alias StarterKit.Audit.AuditEvent

  page "admin/audit-events/index",
    props: [
      events: {:list, Serializers.AuditEventSerializer},
      pagination: Serializers.PaginationSerializer,
      q: :string
    ]

  def index(conn, params) do
    conn = authorize!(conn, :index, AuditEvent)
    page = Audit.list_events(scope(conn), params)

    render_inertia(conn, "admin/audit-events/index", %{
      events: Serializers.AuditEventSerializer.serialize_many(page.entries),
      pagination: Serializers.PaginationSerializer.serialize(page),
      q: params["q"] || ""
    })
  end
end
