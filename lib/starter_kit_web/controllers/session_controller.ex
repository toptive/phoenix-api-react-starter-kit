defmodule StarterKitWeb.SessionController do
  @moduledoc """
  Sign in and out. `create` accepts either a magic-link token (from the confirmation
  page) or email + password.
  """
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.{Accounts, Analytics}
  alias StarterKitWeb.UserAuth

  page "session/new",
    props: [
      google_enabled: :boolean,
      email_available: :boolean,
      reauthenticating: :boolean,
      link_sent_to: {:nullable, :string},
      new_account: :boolean,
      signup_mode: {:enum, [:open, :invite, :closed]}
    ]

  plug StarterKitWeb.Plugs.RateLimit,
       [bucket: "session", limit: 10, period: 60_000] when action == :create

  # `link_sent_to`: after sign-up or "email me a link", the page shows where the link went.
  # Without mail there is no link form and never a "check your email" state.
  def new(conn, _params) do
    email_available = Accounts.email_sign_in_available?()
    sent_to = if email_available, do: get_session(conn, :link_sent_to)
    new_account = get_session(conn, :link_sent_new) == true

    conn
    |> skip_authorization()
    |> delete_session(:link_sent_to)
    |> delete_session(:link_sent_new)
    |> render_inertia("session/new", %{
      google_enabled: google_enabled?(),
      email_available: email_available,
      reauthenticating: not is_nil(conn.assigns.current_scope),
      link_sent_to: sent_to,
      new_account: new_account,
      signup_mode: Accounts.signup_mode()
    })
  end

  def create(conn, %{"user" => %{"token" => token} = params}) do
    conn = skip_authorization(conn)

    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, expired_tokens}} ->
        Analytics.track("user_signed_in", user, %{method: "magic_link"})
        # Confirming a new account expires its tokens; a returning user expires none.
        new_account = expired_tokens != []
        if new_account, do: Analytics.track("signup_confirmed", user)
        greeting = if new_account, do: "flash.welcome", else: "flash.signed_in"

        conn
        |> put_flash_t(:info, greeting)
        |> UserAuth.log_in_user(user, params)

      _ ->
        conn
        |> put_flash_t(:error, "flash.magic_link_invalid")
        |> redirect(to: ~p"/session/new")
    end
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password} = params}) do
    conn = skip_authorization(conn)

    if user = Accounts.get_user_by_email_and_password(email, password) do
      Analytics.track("user_signed_in", user, %{method: "password"})

      conn
      |> put_flash_t(:info, "flash.signed_in")
      |> UserAuth.log_in_user(user, params)
    else
      conn
      |> assign_error(:password, "auth.session.invalid_credentials")
      |> redirect(to: ~p"/session/new")
    end
  end

  def delete(conn, _params) do
    conn
    |> skip_authorization()
    |> put_flash_t(:info, "flash.signed_out")
    |> UserAuth.log_out_user()
  end

  defp google_enabled?, do: Application.get_env(:starter_kit, :google_auth, false)
end
