defmodule StarterKitWeb.Api.V1.Auth.GoogleCallbackController do
  @moduledoc "Verifies Google state, signs in and hands the session to web or native."
  use StarterKitWeb, :controller
  alias StarterKit.Organizations
  alias StarterKitWeb.ApiAuth
  plug StarterKitWeb.Plugs.RateLimit, bucket: "api_google_callback", limit: 20, period: 60_000

  def create(conn, params) do
    conn = skip_authorization(conn)

    if Application.get_env(:starter_kit, :google_auth, false) do
      case ApiAuth.google_state(params["state"]) do
        {:ok, state} ->
          result =
            Organizations.create_google_api_session(
              params["code"],
              ApiAuth.google_callback_url(),
              state.locale,
              ApiAuth.device(conn)
            )

          ApiAuth.google_result(conn, result, state)

        {:error, reason} ->
          ApiAuth.google_result(conn, {:error, reason})
      end
    else
      render_error(conn, 404, :not_found)
    end
  end
end
