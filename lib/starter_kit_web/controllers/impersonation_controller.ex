defmodule StarterKitWeb.ImpersonationController do
  @moduledoc "Ends an impersonation (the banner's \"Back to my account\" button)."
  use StarterKitWeb, :controller

  alias StarterKit.Accounts
  alias StarterKitWeb.UserAuth

  def delete(conn, _params) do
    conn = skip_authorization(conn)

    case conn.assigns.current_scope && Accounts.stop_impersonation(conn.assigns.current_scope) do
      {:ok, admin} ->
        conn
        |> UserAuth.stop_impersonation()
        |> put_flash(:info, StarterKit.I18n.t("flash.impersonation.stopped", %{}, admin.locale))
        |> redirect(to: ~p"/admin/users")

      _ ->
        redirect(conn, to: ~p"/")
    end
  end
end
