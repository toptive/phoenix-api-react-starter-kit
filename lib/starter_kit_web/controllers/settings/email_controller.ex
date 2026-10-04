defmodule StarterKitWeb.Settings.EmailController do
  @moduledoc "Change the sign-in email (confirmed through a link sent to the new address)."
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.Accounts

  page "settings/email/edit", props: []

  def edit(conn, _params) do
    conn |> authorize!(:edit, scope(conn).user) |> render_inertia("settings/email/edit")
  end

  def update(conn, %{"user" => params}) do
    conn = authorize!(conn, :update, scope(conn).user)

    case Accounts.request_email_change(
           scope(conn),
           params,
           &url(~p"/settings/email-confirmations/#{&1}")
         ) do
      {:ok, applied} ->
        conn
        |> put_flash_t(:info, "flash.email.confirmation_sent", %{email: applied.email})
        |> redirect(to: ~p"/settings/email/edit")

      {:error, :email_unavailable} ->
        conn
        |> put_flash_t(:error, "flash.email_unavailable")
        |> redirect(to: ~p"/settings/email/edit")

      {:error, changeset} ->
        conn |> assign_changeset_errors(changeset) |> redirect(to: ~p"/settings/email/edit")
    end
  end
end
