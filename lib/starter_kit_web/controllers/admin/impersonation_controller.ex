defmodule StarterKitWeb.Admin.ImpersonationController do
  @moduledoc "Start acting as a user (reason required, audited)."
  use StarterKitWeb, :controller

  alias StarterKit.Accounts
  alias StarterKitWeb.UserAuth

  def create(conn, %{"user_id" => user_id, "impersonation" => params}) do
    target = Accounts.get_user!(scope(conn), user_id)
    conn = authorize!(conn, :impersonate, target)

    case Accounts.start_impersonation(scope(conn), target, params) do
      {:ok, _impersonation} ->
        conn
        |> UserAuth.start_impersonation(target)
        |> put_flash(
          :info,
          StarterKit.I18n.t("flash.impersonation.started", %{email: target.email}, target.locale)
        )
        |> redirect(to: ~p"/dashboard")

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> assign_changeset_errors(changeset) |> redirect(to: ~p"/admin/users/#{user_id}")

      {:error, :forbidden} ->
        conn
        |> put_flash_t(:error, "flash.impersonation.forbidden")
        |> redirect(to: ~p"/admin/users/#{user_id}")
    end
  end
end
