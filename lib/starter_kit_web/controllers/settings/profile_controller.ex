defmodule StarterKitWeb.Settings.ProfileController do
  @moduledoc "Name and language."
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.Accounts

  page "settings/profile/edit", props: []

  def edit(conn, _params) do
    conn |> authorize!(:edit, scope(conn).user) |> render_inertia("settings/profile/edit")
  end

  def update(conn, %{"user" => params}) do
    conn = authorize!(conn, :update, scope(conn).user)

    case Accounts.update_profile(scope(conn), params) do
      {:ok, user} ->
        conn
        |> put_session(:locale, user.locale)
        |> assign(:locale, user.locale)
        |> put_flash_t(:info, "flash.profile.updated")
        |> redirect(to: ~p"/settings/profile/edit")

      {:error, changeset} ->
        conn |> assign_changeset_errors(changeset) |> redirect(to: ~p"/settings/profile/edit")
    end
  end
end
