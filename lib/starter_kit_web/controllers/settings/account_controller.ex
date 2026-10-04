defmodule StarterKitWeb.Settings.AccountController do
  @moduledoc """
  Delete the account (explains the consequence first). When something stops the
  deletion (an organization would lose its last owner, or a subscription is still open),
  the page says what to do first.
  """
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.Privacy
  alias StarterKitWeb.UserAuth

  page "settings/account/edit",
    props: [
      blocker:
        {:nullable,
         {:object,
          reason: {:enum, [:transfer_ownership, :subscription_active]}, organization: :string}}
    ]

  def edit(conn, _params) do
    conn = authorize!(conn, :edit, scope(conn).user)

    blocker =
      case Privacy.deletion_blocker(scope(conn)) do
        {reason, organization} -> %{reason: reason, organization: organization.name}
        nil -> nil
      end

    render_inertia(conn, "settings/account/edit", %{blocker: blocker})
  end

  def delete(conn, _params) do
    conn = authorize!(conn, :delete, scope(conn).user)

    case Privacy.delete_account(scope(conn)) do
      {:ok, _} ->
        conn |> put_flash_t(:info, "flash.account.deleted") |> UserAuth.log_out_user()

      {:error, :transfer_ownership} ->
        conn
        |> put_flash_t(:error, "flash.account.transfer_ownership")
        |> redirect(to: ~p"/settings/account/edit")

      {:error, :subscription_active} ->
        conn
        |> put_flash_t(:error, "flash.account.subscription_active")
        |> redirect(to: ~p"/settings/account/edit")
    end
  end
end
