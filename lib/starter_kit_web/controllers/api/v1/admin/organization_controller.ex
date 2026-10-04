defmodule StarterKitWeb.Api.V1.Admin.OrganizationController do
  @moduledoc "Superadmin organization API."
  use StarterKitWeb, :controller
  alias StarterKit.Organizations
  alias StarterKit.Organizations.Organization
  alias StarterKitWeb.ApiAuth

  def index(conn, params) do
    conn = authorize!(conn, :index, Organization)
    page = Organizations.list_organizations(scope(conn), params)

    render_collection(conn, page.entries, Serializers.AdminOrganizationSerializer, %{
      pagination: Serializers.PaginationSerializer.serialize(page)
    })
  end

  def show(conn, %{"id" => id}) do
    conn = authorize!(conn, :show, Organization)

    case Organizations.admin_organization_detail(scope(conn), id) do
      {:ok, detail} -> render_data(conn, {Serializers.AdminOrganizationDetailSerializer, detail})
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end
end
