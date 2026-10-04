defmodule StarterKitWeb.Api.V1.Settings.MembershipController do
  @moduledoc "Lists and manages the current organization's people, including leaving."
  use StarterKitWeb, :controller
  alias StarterKit.Organizations
  alias StarterKit.Organizations.Membership
  alias StarterKitWeb.ApiAuth

  def index(conn, _params) do
    conn = authorize!(conn, :index, Membership)

    render_collection(
      conn,
      Organizations.list_memberships(scope(conn)),
      Serializers.MembershipSerializer,
      %{}
    )
  end

  def update(conn, %{"id" => id} = params) do
    conn = authorize!(conn, :update, Membership)

    case Organizations.update_member(scope(conn), id, Map.take(params, ["role", "access"])) do
      {:ok, membership} -> render_data(conn, {Serializers.MembershipSerializer, membership})
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end

  def delete(conn, %{"id" => id}) do
    conn = authorize!(conn, :delete, Membership)

    case Organizations.remove_member(scope(conn), id) do
      {:ok, _} -> send_resp(conn, 204, "")
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end
end
