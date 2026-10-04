defmodule StarterKitWeb.Admin.OrganizationController do
  @moduledoc "All organizations and their members."
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.Organizations
  alias StarterKit.Organizations.Organization

  page "admin/organizations/index",
    props: [
      organizations: {:list, Serializers.AdminOrganizationSerializer},
      pagination: Serializers.PaginationSerializer,
      q: :string
    ]

  page "admin/organizations/show",
    props: [
      organization: Serializers.OrganizationSerializer,
      memberships: {:list, Serializers.MembershipSerializer}
    ]

  def index(conn, params) do
    conn = authorize!(conn, :index, Organization)
    page = Organizations.list_organizations(scope(conn), params)

    render_inertia(conn, "admin/organizations/index", %{
      organizations: Serializers.AdminOrganizationSerializer.serialize_many(page.entries),
      pagination: Serializers.PaginationSerializer.serialize(page),
      q: params["q"] || ""
    })
  end

  def show(conn, %{"id" => id}) do
    organization = Organizations.get_organization!(scope(conn), id)
    conn = authorize!(conn, :show, organization)

    render_inertia(conn, "admin/organizations/show", %{
      organization: Serializers.OrganizationSerializer.serialize(organization),
      memberships:
        Serializers.MembershipSerializer.serialize_many(
          Organizations.list_organization_memberships(organization)
        )
    })
  end
end
