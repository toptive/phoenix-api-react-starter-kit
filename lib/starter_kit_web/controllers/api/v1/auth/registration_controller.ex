defmodule StarterKitWeb.Api.V1.Auth.RegistrationController do
  @moduledoc "Registration with consent, sign-up mode guards and Turnstile."
  use StarterKitWeb, :controller
  alias StarterKit.{Analytics, Organizations}
  alias StarterKitWeb.ApiAuth

  plug StarterKitWeb.Plugs.RateLimit, bucket: "api_registration", limit: 10, period: 60_000
  plug StarterKitWeb.Plugs.VerifyTurnstile, "registration"

  def create(conn, params) do
    conn = skip_authorization(conn)
    attrs = Map.put_new(params, "locale", locale(conn))

    case Organizations.register_user(attrs, &ApiAuth.spa_url("/auth/magic-links/#{&1}"),
           ip_address: ApiAuth.device(conn).ip_address
         ) do
      {:ok, user} ->
        Analytics.track("user_registered", user, %{via: "email"})

        conn
        |> put_status(202)
        |> render_data(
          {Serializers.MagicLinkRequestSerializer, %{email: user.email, new_account: true}}
        )

      {:error, reason} ->
        ApiAuth.error(conn, reason)
    end
  end
end
