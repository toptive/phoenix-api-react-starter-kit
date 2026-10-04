defmodule StarterKitWeb.Api.V1.OrganizationController do
  @moduledoc "Creates an organization owned by the caller in multi mode."
  use StarterKitWeb, :controller
  alias StarterKit.{Analytics, Organizations}
  alias StarterKit.Organizations.Organization
  alias StarterKitWeb.ApiAuth

  def create(conn, params) do
    conn = authorize!(conn, :create, Organization)

    case Organizations.create_current_organization(scope(conn), Map.take(params, ["name"])) do
      {:ok, org} ->
        Analytics.track("organization_created", scope(conn))
        conn |> put_status(201) |> render_data({Serializers.OrganizationSerializer, org})

      {:error, reason} ->
        ApiAuth.error(conn, reason)
    end
  end
end
