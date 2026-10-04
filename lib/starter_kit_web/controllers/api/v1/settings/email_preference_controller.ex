defmodule StarterKitWeb.Api.V1.Settings.EmailPreferenceController do
  @moduledoc "Account email preference settings through the JSON API."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts
  alias StarterKitWeb.ApiAuth

  def show(conn, _params) do
    conn = authorize!(conn, :show, scope(conn).user)
    render_data(conn, {Serializers.EmailPreferencesSerializer, scope(conn).user})
  end

  def update(conn, params) do
    conn = authorize!(conn, :update, scope(conn).user)

    case Accounts.update_email_preferences(scope(conn), Map.take(params, ["optional_emails"])) do
      {:ok, user} -> render_data(conn, {Serializers.EmailPreferencesSerializer, user})
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end
end
