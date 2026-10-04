defmodule StarterKitWeb.InvitationController do
  @moduledoc "The page behind an invitation link. Works signed in or out."
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.Organizations

  page "invitations/show",
    props: [
      token: :string,
      invitation:
        {:object,
         organization: :string,
         email: :string,
         role: {:enum, [:owner, :admin, :member]},
         access: {:enum, [:full, :viewer]}},
      email_matches: :boolean
    ]

  def show(conn, %{"token" => token}) do
    conn = skip_authorization(conn)

    case Organizations.get_open_invitation(token) do
      {:ok, invitation} ->
        user = conn.assigns.current_scope && conn.assigns.current_scope.user

        conn
        |> put_session(:user_return_to, ~p"/invitations/#{token}")
        |> render_inertia("invitations/show", %{
          token: token,
          invitation: %{
            organization: invitation.organization.name,
            email: invitation.email,
            role: invitation.role,
            access: invitation.access
          },
          email_matches: not is_nil(user) and String.downcase(user.email) == invitation.email
        })

      {:error, _} ->
        conn |> put_flash_t(:error, "flash.invitation.invalid") |> redirect(to: ~p"/")
    end
  end
end
