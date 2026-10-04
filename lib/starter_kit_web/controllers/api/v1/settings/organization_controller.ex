defmodule StarterKitWeb.Api.V1.Settings.OrganizationController do
  @moduledoc "Reads and updates the current organization's settings."
  use StarterKitWeb, :controller
  alias StarterKit.Organizations
  alias StarterKitWeb.ApiAuth

  def show(conn, _params) do
    conn = authorize!(conn, :show, scope(conn).organization)

    render_data(
      conn,
      {Serializers.OrganizationSettingsSerializer, Organizations.organization_settings(scope(conn))}
    )
  end

  def update(conn, params) do
    conn = authorize!(conn, :update, scope(conn).organization)

    case Organizations.update_organization(
           scope(conn),
           scope(conn).organization,
           Map.take(params, ["name"])
         ) do
      {:ok, org} -> render_data(conn, {Serializers.OrganizationSerializer, org})
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end
end
