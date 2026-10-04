defmodule StarterKitWeb.Settings.OrganizationController do
  @moduledoc "The current organization's name."
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.Organizations

  page "settings/organization/edit", props: [can_edit: :boolean]

  def edit(conn, _params) do
    organization = scope(conn).organization

    conn
    |> authorize!(:show, organization)
    |> render_inertia("settings/organization/edit", %{can_edit: can?(conn, :update, organization)})
  end

  def update(conn, %{"organization" => params}) do
    organization = scope(conn).organization
    conn = authorize!(conn, :update, organization)

    case Organizations.update_organization(scope(conn), organization, params) do
      {:ok, _} ->
        conn
        |> put_flash_t(:info, "flash.organization.updated")
        |> redirect(to: ~p"/settings/organization/edit")

      {:error, changeset} ->
        conn |> assign_changeset_errors(changeset) |> redirect(to: ~p"/settings/organization/edit")
    end
  end
end
