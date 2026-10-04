defmodule StarterKitWeb.Settings.MembershipController do
  @moduledoc """
  The "People" screen: members and pending invitations of the current organization in
  one place (one user task, even if it is two tables).
  """
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.Organizations
  alias StarterKit.Organizations.{Invitation, Membership}

  page "settings/members/index",
    props: [
      memberships: {:list, Serializers.MembershipSerializer},
      invitations: {:list, Serializers.InvitationSerializer},
      can_manage: :boolean
    ]

  def index(conn, _params) do
    conn = authorize!(conn, :index, Membership)
    can_manage = can?(conn, :index, Invitation)

    render_inertia(conn, "settings/members/index", %{
      memberships:
        Serializers.MembershipSerializer.serialize_many(Organizations.list_memberships(scope(conn))),
      invitations:
        if(can_manage,
          do:
            Serializers.InvitationSerializer.serialize_many(
              Organizations.list_invitations(scope(conn))
            ),
          else: []
        ),
      can_manage: can_manage
    })
  end

  def update(conn, %{"id" => id, "membership" => params}) do
    membership = Organizations.get_membership!(scope(conn), id)
    conn = authorize!(conn, :update, membership)

    case Organizations.update_membership(scope(conn), membership, params) do
      {:ok, _} -> conn |> put_flash_t(:info, "flash.membership.updated")
      {:error, changeset} -> conn |> assign_changeset_errors(changeset)
    end
    |> redirect(to: ~p"/settings/members")
  end

  def delete(conn, %{"id" => id}) do
    membership = Organizations.get_membership!(scope(conn), id)
    conn = authorize!(conn, :delete, membership)
    leaving? = membership.user_id == scope(conn).user.id

    case Organizations.delete_membership(scope(conn), membership) do
      {:ok, _} when leaving? ->
        conn
        |> delete_session(:organization_id)
        |> put_flash_t(:info, "flash.membership.left")
        |> redirect(to: ~p"/dashboard")

      {:ok, _} ->
        conn
        |> put_flash_t(:info, "flash.membership.removed")
        |> redirect(to: ~p"/settings/members")

      {:error, :last_owner} ->
        conn
        |> put_flash_t(:error, "flash.membership.last_owner")
        |> redirect(to: ~p"/settings/members")
    end
  end
end
