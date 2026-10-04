defmodule StarterKitWeb.Api.V1.Settings.ProfileController do
  @moduledoc "Account profile settings through the JSON API."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts
  alias StarterKitWeb.ApiAuth

  def update(conn, params) do
    conn = authorize!(conn, :update, scope(conn).user)

    case Accounts.update_profile(scope(conn), Map.take(params, ["name", "locale"])) do
      {:ok, user} -> render_data(conn, {Serializers.UserSerializer, user})
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end
end
