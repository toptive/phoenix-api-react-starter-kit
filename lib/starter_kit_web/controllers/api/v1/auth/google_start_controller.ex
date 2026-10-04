defmodule StarterKitWeb.Api.V1.Auth.GoogleStartController do
  @moduledoc "Starts Google OAuth using signed, browser-bound state."
  use StarterKitWeb, :controller
  alias StarterKitWeb.ApiAuth
  plug StarterKitWeb.Plugs.RateLimit, bucket: "api_google_start", limit: 10, period: 60_000

  def show(conn, _params) do
    conn = skip_authorization(conn)

    if Application.get_env(:starter_kit, :google_auth, false),
      do: ApiAuth.start_google(conn),
      else: render_error(conn, 404, :not_found)
  end
end
