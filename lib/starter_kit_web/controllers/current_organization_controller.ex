defmodule StarterKitWeb.CurrentOrganizationController do
  @moduledoc "Switching organization = updating the current-organization resource."
  use StarterKitWeb, :controller

  alias StarterKit.Organizations
  alias StarterKit.Organizations.Organization

  def update(conn, %{"organization_id" => organization_id}) do
    conn = authorize!(conn, :switch, %Organization{id: organization_id})

    case Organizations.switch_organization(scope(conn), organization_id) do
      {:ok, _scope} ->
        conn
        |> put_session(:organization_id, organization_id)
        |> redirect(to: ~p"/dashboard")

      {:error, :not_member} ->
        raise StarterKitWeb.NotAuthorizedError, action: :switch, resource: Organization
    end
  end
end
