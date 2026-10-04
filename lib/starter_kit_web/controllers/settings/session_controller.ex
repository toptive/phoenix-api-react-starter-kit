defmodule StarterKitWeb.Settings.SessionController do
  @moduledoc "The devices signed in to this account; sign any of them out."
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.Accounts

  page "settings/sessions/index",
    props: [
      sessions: {:list, Serializers.SessionSerializer},
      current_session_id: {:nullable, :string}
    ]

  def index(conn, _params) do
    conn = authorize!(conn, :show, scope(conn).user)
    sessions = Accounts.list_sessions(scope(conn))
    current_token = get_session(conn, :user_token)
    current = Enum.find(sessions, &(&1.token == current_token))

    render_inertia(conn, "settings/sessions/index", %{
      sessions: Serializers.SessionSerializer.serialize_many(sessions),
      current_session_id: current && current.id
    })
  end

  def delete(conn, %{"id" => id}) do
    conn = authorize!(conn, :update, scope(conn).user)

    case Accounts.revoke_session(scope(conn), id) do
      {:ok, _} -> conn |> put_flash_t(:info, "flash.session.revoked")
      {:error, _} -> conn |> put_flash_t(:error, "flash.session.not_found")
    end
    |> redirect(to: ~p"/settings/sessions")
  end
end
