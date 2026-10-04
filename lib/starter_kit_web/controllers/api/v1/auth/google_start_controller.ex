defmodule StarterKitWeb.Api.V1.Auth.GoogleStartController do
  @moduledoc "Starts Google OAuth using signed, cookie-free state."
  use StarterKitWeb, :controller
  alias StarterKitWeb.ApiAuth

  def show(conn, params) do
    conn = skip_authorization(conn)

    if Application.get_env(:starter_kit, :google_auth, false),
      do: ApiAuth.start_google(conn, params),
      else: render_error(conn, 404, :not_found)
  end
end
