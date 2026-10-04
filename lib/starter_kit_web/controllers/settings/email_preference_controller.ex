defmodule StarterKitWeb.Settings.EmailPreferenceController do
  @moduledoc """
  Optional mail (news and tips) on or off. The way back after a one-click unsubscribe
  (`EmailOptOutController`), and the "Email preferences" link in optional mail.
  """
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.Accounts

  page "settings/email-preferences/edit", props: [optional_emails: :boolean]

  def edit(conn, _params) do
    user = scope(conn).user

    conn
    |> authorize!(:edit, user)
    |> render_inertia("settings/email-preferences/edit", %{optional_emails: user.optional_emails})
  end

  def update(conn, %{"user" => params}) do
    conn = authorize!(conn, :update, scope(conn).user)

    case Accounts.update_email_preferences(scope(conn), params) do
      {:ok, _user} ->
        conn
        |> put_flash_t(:info, "flash.email_preferences.updated")
        |> redirect(to: ~p"/settings/email-preferences/edit")

      {:error, changeset} ->
        conn
        |> assign_changeset_errors(changeset)
        |> redirect(to: ~p"/settings/email-preferences/edit")
    end
  end
end
