defmodule StarterKitWeb.Api.V1.CurrentOrganizationController do
  @moduledoc "Switches the current organization for this device."
  use StarterKitWeb, :controller
  alias StarterKit.Organizations
  alias StarterKitWeb.ApiAuth

  def update(conn, %{"organization_id" => id}) do
    conn = authorize!(conn, :switch, scope(conn).organization)

    if is_binary(id) do
      case Organizations.switch_current_organization(scope(conn), id) do
        {:ok, auth} -> render_data(conn, {Serializers.AuthSerializer, auth})
        {:error, reason} -> ApiAuth.error(conn, reason)
      end
    else
      render_error(conn, 400, :bad_request)
    end
  end

  def update(conn, _params),
    do: conn |> authorize!(:switch, scope(conn).organization) |> render_error(400, :bad_request)
end
