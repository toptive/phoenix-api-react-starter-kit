defmodule StarterKitWeb.InvitationAcceptanceController do
  @moduledoc "Accepting an invitation creates the membership."
  use StarterKitWeb, :controller

  alias StarterKit.{Analytics, Organizations}

  def create(conn, %{"invitation_token" => token}) do
    conn = skip_authorization(conn)

    case Organizations.accept_invitation(scope(conn), token) do
      {:ok, membership} ->
        Analytics.track("invitation_accepted", scope(conn))

        conn
        |> delete_session(:user_return_to)
        |> put_session(:organization_id, membership.organization_id)
        |> put_flash_t(:info, "flash.invitation.accepted")
        |> redirect(to: ~p"/dashboard")

      {:error, :email_mismatch} ->
        conn
        |> put_flash_t(:error, "flash.invitation.email_mismatch")
        |> redirect(to: ~p"/invitations/#{token}")

      {:error, _} ->
        conn |> put_flash_t(:error, "flash.invitation.invalid") |> redirect(to: ~p"/dashboard")
    end
  end
end
