defmodule StarterKitWeb.OAuthController do
  @moduledoc """
  Google sign-in through Ueberauth (optional: on when `GOOGLE_CLIENT_ID` is set).
  `new` starts the flow (Ueberauth redirects to Google); `create` is the callback.
  """
  use StarterKitWeb, :controller

  alias StarterKit.{Analytics, Organizations}
  alias StarterKitWeb.UserAuth

  plug :require_enabled
  plug Ueberauth

  def new(conn, _params), do: conn |> skip_authorization() |> redirect(to: ~p"/session/new")

  def create(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    conn = skip_authorization(conn)

    info = %{
      uid: to_string(auth.uid),
      email: auth.info.email,
      email_verified: email_verified?(auth),
      name: auth.info.name,
      locale: locale(conn)
    }

    case Organizations.upsert_google_user(info) do
      {:ok, user} ->
        Analytics.track("user_signed_in", user, %{method: "google"})

        conn
        |> put_flash_t(:info, "flash.signed_in")
        |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

      {:error, reason} when reason in [:invitation_required, :signup_closed] ->
        conn |> put_flash_t(:error, signup_refused(reason)) |> redirect(to: ~p"/session/new")

      {:error, _} ->
        conn |> put_flash_t(:error, "flash.oauth_failed") |> redirect(to: ~p"/session/new")
    end
  end

  def create(conn, _params) do
    conn
    |> skip_authorization()
    |> put_flash_t(:error, "flash.oauth_failed")
    |> redirect(to: ~p"/session/new")
  end

  # Google's userinfo claim. A missing claim counts as not verified.
  defp email_verified?(%{extra: %{raw_info: %{user: %{"email_verified" => true}}}}), do: true
  defp email_verified?(_auth), do: false

  defp require_enabled(conn, _opts) do
    if Application.get_env(:starter_kit, :google_auth, false) do
      conn
    else
      conn
      |> skip_authorization()
      |> put_status(404)
      |> put_view(StarterKitWeb.ErrorHTML)
      |> render(:"404")
      |> halt()
    end
  end

  defp signup_refused(:invitation_required), do: "flash.invitation_required"
  defp signup_refused(:signup_closed), do: "flash.signup_closed"
end
