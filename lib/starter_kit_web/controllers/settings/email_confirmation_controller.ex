defmodule StarterKitWeb.Settings.EmailConfirmationController do
  @moduledoc """
  The link in the "confirm your new email" message. `show` is a page with one button;
  only `create` (the button's POST) changes the email, so a link scanner that opens the
  link cannot use the token. The token is single-use and bound to the signed-in user.
  """
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.Accounts

  page "settings/email-confirmations/show", props: [token: :string, email: :string]

  def show(conn, %{"token" => token}) do
    user = scope(conn).user
    conn = authorize!(conn, :update, user)

    case Accounts.get_email_change(user, token) do
      nil ->
        conn
        |> put_flash_t(:error, "flash.email.link_invalid")
        |> redirect(to: ~p"/settings/email/edit")

      email ->
        render_inertia(conn, "settings/email-confirmations/show", %{token: token, email: email})
    end
  end

  def create(conn, %{"token" => token}) do
    conn = authorize!(conn, :update, scope(conn).user)

    case Accounts.update_user_email(scope(conn).user, token) do
      {:ok, _user} -> put_flash_t(conn, :info, "flash.email.changed")
      {:error, _} -> put_flash_t(conn, :error, "flash.email.link_invalid")
    end
    |> redirect(to: ~p"/settings/email/edit")
  end
end
