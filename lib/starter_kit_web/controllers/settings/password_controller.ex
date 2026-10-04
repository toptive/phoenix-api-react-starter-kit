defmodule StarterKitWeb.Settings.PasswordController do
  @moduledoc "Set or change the password. Every other session ends."
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.Accounts
  alias StarterKitWeb.UserAuth

  page "settings/password/edit", props: []

  def edit(conn, _params) do
    conn |> authorize!(:edit, scope(conn).user) |> render_inertia("settings/password/edit")
  end

  def update(conn, %{"user" => params}) do
    conn = authorize!(conn, :update, scope(conn).user)

    case Accounts.update_user_password(scope(conn), params) do
      {:ok, {user, _expired}} ->
        conn
        |> put_session(:user_return_to, ~p"/settings/password/edit")
        |> put_flash_t(:info, "flash.password.updated")
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        conn |> assign_changeset_errors(changeset) |> redirect(to: ~p"/settings/password/edit")
    end
  end
end
