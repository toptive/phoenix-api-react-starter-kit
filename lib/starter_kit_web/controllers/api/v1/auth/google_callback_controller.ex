defmodule StarterKitWeb.Api.V1.Auth.GoogleCallbackController do
  @moduledoc "Google callback: validates state, issues a bearer token and returns to the SPA."
  use StarterKitWeb, :controller
  alias StarterKit.Organizations
  alias StarterKitWeb.ApiAuth
  plug StarterKitWeb.Plugs.RateLimit, bucket: "api_google_callback", limit: 10, period: 60_000

  def create(conn, %{"code" => code, "state" => state}) do
    conn = skip_authorization(conn)

    with true <- is_binary(code),
         true <- Application.get_env(:starter_kit, :google_auth, false),
         {:ok, locale} <- ApiAuth.google_state(conn, state) do
      ApiAuth.google_result(
        conn,
        Organizations.create_google_api_session(
          code,
          ApiAuth.google_callback_url(),
          locale,
          ApiAuth.device(conn)
        )
      )
    else
      _ -> ApiAuth.google_result(conn, {:error, :oauth_failed})
    end
  end

  def create(conn, _params),
    do: conn |> skip_authorization() |> ApiAuth.google_result({:error, :oauth_failed})
end
