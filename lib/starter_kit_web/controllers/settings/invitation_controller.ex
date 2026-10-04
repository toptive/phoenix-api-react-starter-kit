defmodule StarterKitWeb.Settings.InvitationController do
  @moduledoc "Invite people to the current organization, or revoke an invitation."
  use StarterKitWeb, :controller

  alias StarterKit.{Analytics, Organizations}
  alias StarterKit.Organizations.Invitation

  plug StarterKitWeb.Plugs.RateLimit,
       [bucket: "invitation", limit: 30, period: 3_600_000] when action == :create

  def create(conn, %{"invitation" => params}) do
    conn = authorize!(conn, :create, Invitation)

    case Organizations.create_invitation(scope(conn), params, &url(~p"/invitations/#{&1}")) do
      {:ok, invitation} ->
        Analytics.track("invitation_sent", scope(conn), %{role: invitation.role})

        conn
        |> put_flash_t(:info, "flash.invitation.sent", %{email: invitation.email})
        |> redirect(to: ~p"/settings/members")

      {:error, :email_unavailable} ->
        conn
        |> put_flash_t(:error, "flash.email_unavailable")
        |> redirect(to: ~p"/settings/members")

      {:error, changeset} ->
        conn |> assign_changeset_errors(changeset) |> redirect(to: ~p"/settings/members")
    end
  end

  def delete(conn, %{"id" => id}) do
    invitation = Organizations.get_invitation!(scope(conn), id)
    conn = authorize!(conn, :delete, invitation)
    {:ok, _} = Organizations.delete_invitation(scope(conn), invitation)

    conn |> put_flash_t(:info, "flash.invitation.revoked") |> redirect(to: ~p"/settings/members")
  end
end
