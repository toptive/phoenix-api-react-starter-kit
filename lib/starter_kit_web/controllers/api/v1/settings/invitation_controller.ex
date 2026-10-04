defmodule StarterKitWeb.Api.V1.Settings.InvitationController do
  @moduledoc "Lists, sends and revokes invitations for this tenant."
  use StarterKitWeb, :controller
  alias StarterKit.{Analytics, Billing, Organizations}
  alias StarterKit.Organizations.Invitation
  alias StarterKitWeb.ApiAuth

  plug StarterKitWeb.Plugs.RateLimit,
       [bucket: "api_invitation", limit: 30, period: 3_600_000] when action == :create

  def index(conn, _params) do
    conn = authorize!(conn, :index, Invitation)

    render_collection(
      conn,
      Organizations.list_invitations(scope(conn)),
      Serializers.InvitationSerializer,
      %{}
    )
  end

  def create(conn, params) do
    conn = authorize!(conn, :create, Invitation)

    case Billing.invite_member(
           scope(conn),
           Map.take(params, ["email", "role", "access"]),
           &ApiAuth.spa_url("/invitations/#{&1}"),
           locale(conn)
         ) do
      {:ok, invitation} ->
        Analytics.track("invitation_sent", scope(conn), %{role: invitation.role})
        conn |> put_status(201) |> render_data({Serializers.InvitationSerializer, invitation})

      {:error, reason} ->
        ApiAuth.error(conn, reason)
    end
  end

  def delete(conn, %{"id" => id}) do
    conn = authorize!(conn, :index, Invitation)

    case Organizations.revoke_invitation(scope(conn), id) do
      {:ok, _} -> send_resp(conn, 204, "")
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end
end
