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

  @doc "Starts Google with signed state and no cookie."
  def start_google(conn, params) do
    client = params["client"] || "web"
    return_to = params["return_to"] || "/dashboard"

    if client in ["web", "native"] and valid_return_to?(return_to) do
      state =
        Phoenix.Token.sign(StarterKitWeb.Endpoint, "google-api-state", %{
          nonce: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false),
          client: client,
          returnTo: return_to,
          locale: Responses.locale(conn),
          iat: System.system_time(:second)
        })

      config = Application.get_env(:ueberauth, Ueberauth.Strategy.Google.OAuth, [])

      query =
        URI.encode_query(%{
          client_id: config[:client_id],
          redirect_uri: google_callback_url(),
          response_type: "code",
          scope: "openid email profile",
          prompt: "select_account",
          state: state
        })

      Phoenix.Controller.redirect(conn,
        external: "https://accounts.google.com/o/oauth2/v2/auth?" <> query
      )
    else
      Responses.render_error(conn, 400, :bad_request)
    end
  end

  defp valid_return_to?(path) when is_binary(path) do
    String.starts_with?(path, "/") and String.length(path) <= 200 and
      not String.contains?(path, ["//", "\\", "\r", "\n"])
  end

  defp valid_return_to?(_path), do: false

  @doc "Verifies the signed state and its ten-minute window."
  def google_state(state) when is_binary(state) do
    with {:ok, %{client: client, returnTo: return_to, locale: locale, iat: iat} = payload} <-
           Phoenix.Token.verify(StarterKitWeb.Endpoint, "google-api-state", state, max_age: 600),
         true <- client in ["web", "native"] and valid_return_to?(return_to),
         true <- locale in StarterKit.I18n.locales(),
         true <-
           is_integer(iat) and iat <= System.system_time(:second) and
             System.system_time(:second) - iat <= 600 do
      {:ok, payload}
    else
      _ -> {:error, :state_invalid}
    end
  end

  def google_state(_state), do: {:error, :state_invalid}

  @doc "Returns tokens in a fragment to the configured web or native handoff."
  def google_result(conn, result, state \\ %{}) do
    conn =
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("referrer-policy", "no-referrer")

    fragment =
      case result do
        {:ok, session} ->
          Analytics.track("user_signed_in", session.user, %{method: "google"})

          if session.new_account,
            do: Analytics.track("user_registered", session.user, %{via: "google"})

          URI.encode_query([
            {"token", session.token},
            {"expiresAt", DateTime.to_iso8601(session.expires_at)},
            {"new", if(session.new_account, do: "1", else: "0")},
            {"returnTo", state[:returnTo] || "/dashboard"}
          ])

        {:error, reason} ->
          URI.encode_query(%{error: reason})
      end

    destination =
      if state[:client] == "native",
        do: Application.fetch_env!(:starter_kit, :native_scheme) <> "://auth/callback",
        else: spa_url("/auth/callback")

    Phoenix.Controller.redirect(conn, external: destination <> "#" <> fragment)
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

  def error(conn, {:limit_reached, :members, limit}) do
    Responses.render_error(conn, 422, :validation_failed, %{
      email: [
        StarterKit.I18n.field_error(
          "validation.limit_reached",
          %{limit: limit},
          Responses.locale(conn)
        )
      ]
    })
  end

  def error(conn, {:email_unchanged, changeset}),
    do:
      Responses.render_error(
        conn,
        409,
        :email_unchanged,
        StarterKit.I18n.validation_details(changeset, Responses.locale(conn))
      )

  def error(conn, {reason, organization})
      when reason in [:transfer_ownership, :subscription_active],
      do: Responses.render_error(conn, 409, reason, %{organization: organization})

  def error(conn, reason) when reason in [:ai_not_configured, :ai_unavailable],
    do: Responses.render_error(conn, 503, reason)

  def error(conn, reason) do
    status =
      case reason do
        :invalid_credentials -> 401
        :forbidden -> 403
        reason when reason in [:not_member, :last_owner, :email_mismatch, :not_impersonating] -> 409
        :not_found -> 404
        :bad_request -> 400
        :email_unavailable -> 503
        _ -> 422
      end

    Responses.render_error(
      conn,
      status,
      if(reason == :not_impersonating, do: :conflict, else: reason)
    )
  end
end
