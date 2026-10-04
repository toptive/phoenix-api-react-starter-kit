defmodule StarterKitWeb.OrganizationController do
  @moduledoc "Create another organization (multi-tenant mode)."
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.{Analytics, Organizations}
  alias StarterKit.Organizations.Organization

  page "organizations/new", props: []

  def new(conn, _params) do
    conn |> authorize_create() |> render_inertia("organizations/new")
  end

  def create(conn, %{"organization" => params}) do
    conn = authorize_create(conn)

    case Organizations.create_user_organization(scope(conn), params) do
      {:ok, organization} ->
        Analytics.track("organization_created", scope(conn))

        conn
        |> put_session(:organization_id, organization.id)
        |> put_flash_t(:info, "flash.organization.created")
        |> redirect(to: ~p"/dashboard")

      {:error, changeset} ->
        conn |> assign_changeset_errors(changeset) |> redirect(to: ~p"/organizations/new")
    end
  end

  # Anyone signed in may create an organization, except in single-tenant mode.
  defp authorize_create(conn) do
    if Organizations.mode() == :multi,
      do: skip_authorization(conn),
      else: raise(StarterKitWeb.NotAuthorizedError, action: :create, resource: Organization)
  end
end
