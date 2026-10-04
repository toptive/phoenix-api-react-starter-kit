defmodule StarterKitWeb.ApiAuth do
  @moduledoc "Shared auth rendering, device metadata and SPA email destinations."
  import Plug.Conn
  alias StarterKit.Analytics
  alias StarterKitWeb.{Responses, Serializers}

  @doc "Device metadata from the resolved peer."
  def device(conn),
    do: %{
      user_agent: List.first(get_req_header(conn, "user-agent")),
      ip_address: to_string(:inet.ntoa(conn.remote_ip))
    }

  @doc "Absolute SPA destination for emailed links."
  def spa_url(path),
    do: String.trim_trailing(Application.fetch_env!(:starter_kit, :spa_origin), "/") <> path

  @doc "Google's fixed API callback URL."
  def google_callback_url, do: StarterKitWeb.Endpoint.url() <> "/api/v1/auth/google/callback"

  @doc "Starts OAuth with a signed state bound to this browser's transient cookie."
  def start_google(conn) do
    nonce = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    state =
      Phoenix.Token.sign(StarterKitWeb.Endpoint, "google-api-state", %{
        nonce: nonce,
        locale: Responses.locale(conn)
      })

    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Google.OAuth, [])

    query =
      URI.encode_query(%{
        client_id: config[:client_id],
        redirect_uri: google_callback_url(),
        response_type: "code",
        scope: "openid email profile",
        state: state
      })

    conn
    |> put_resp_cookie("_api_oauth_state", nonce,
      http_only: true,
      same_site: "Lax",
      secure: Application.get_env(:starter_kit, :secure_cookies, false),
      max_age: 600,
      path: "/api/v1/auth/google"
    )
    |> Phoenix.Controller.redirect(
      external: "https://accounts.google.com/o/oauth2/v2/auth?" <> query
    )
  end

  @doc "Validates signed state and browser binding before exchanging a provider code."
  def google_state(conn, state) when is_binary(state) do
    conn = fetch_cookies(conn)

    with {:ok, %{nonce: nonce, locale: locale}} <-
           Phoenix.Token.verify(StarterKitWeb.Endpoint, "google-api-state", state, max_age: 600),
         cookie when is_binary(cookie) <- conn.cookies["_api_oauth_state"],
         true <- Plug.Crypto.secure_compare(cookie, nonce) do
      {:ok, locale}
    else
      _ -> {:error, :oauth_failed}
    end
  end

  def google_state(_conn, _state), do: {:error, :oauth_failed}

  @doc "Redirects to the SPA using a fragment so tokens never enter its request URL."
  def google_result(conn, result) do
    conn =
      conn
      |> delete_resp_cookie("_api_oauth_state", path: "/api/v1/auth/google")
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("referrer-policy", "no-referrer")

    fragment =
      case result do
        {:ok, session} ->
          Analytics.track("user_signed_in", session.user, %{method: "google"})
          URI.encode_query(%{token: session.token})

        {:error, reason} ->
          URI.encode_query(%{error: reason})
      end

    Phoenix.Controller.redirect(conn, external: spa_url("/auth/callback#" <> fragment))
  end

  @doc "Returns an issued session or the standard error envelope."
  def session_result(conn, {:ok, session}, method) do
    Analytics.track("user_signed_in", session.user, %{method: method})
    if session[:new_account], do: Analytics.track("signup_confirmed", session.user)

    conn
    |> put_status(201)
    |> put_resp_header("cache-control", "private, no-store")
    |> Responses.render_data({Serializers.AuthSessionSerializer, session})
  end

  def session_result(conn, {:error, reason}, _method), do: error(conn, reason)

  @doc "Maps context errors to HTTP statuses, keeping validation message keys."
  def error(conn, %Ecto.Changeset{} = changeset),
    do: Responses.render_validation_error(conn, changeset)

  def error(conn, reason) do
    status =
      case reason do
        :invalid_credentials -> 401
        :forbidden -> 403
        reason when reason in [:signup_closed, :invitation_required] -> 403
        :email_unavailable -> 503
        _ -> 422
      end

    Responses.render_error(conn, status, reason)
  end
end
