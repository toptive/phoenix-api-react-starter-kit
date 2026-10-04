defmodule StarterKitWeb.RegistrationController do
  @moduledoc """
  Sign up: name, email and the accepted terms. The emailed link confirms the address and
  signs in. `SIGNUP_MODE` decides who may sign up (`StarterKit.Accounts.signup_mode/0`).
  """
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.{Accounts, Analytics, Organizations}

  page "registration/new",
    props: [
      email: :string,
      email_available: :boolean,
      signup_mode: {:enum, [:open, :invite, :closed]}
    ]

  plug StarterKitWeb.Plugs.RateLimit,
       [bucket: "registration", limit: 10, period: 60_000] when action == :create

  plug StarterKitWeb.Plugs.VerifyTurnstile, "registration" when action == :create

  # `?email=` pre-fills the form (invitation links). Without mail the page says so up front
  # instead of a form that can only fail.
  def new(conn, params) do
    email = params |> Map.get("email", "") |> to_string() |> String.slice(0, 160)

    conn
    |> skip_authorization()
    |> render_inertia("registration/new", %{
      email: email,
      email_available: Accounts.email_sign_in_available?(),
      signup_mode: Accounts.signup_mode()
    })
  end

  def create(conn, %{"user" => user_params}) do
    conn = skip_authorization(conn)
    attrs = Map.put_new(user_params, "locale", locale(conn))
    ip_address = conn.remote_ip |> :inet.ntoa() |> to_string()

    case Organizations.register_user(attrs, &url(~p"/magic-links/#{&1}"), ip_address: ip_address) do
      {:ok, user} ->
        Analytics.track("user_registered", user, %{via: "email"})

        conn
        |> put_session(:link_sent_to, user.email)
        |> put_session(:link_sent_new, true)
        |> redirect(to: ~p"/session/new")

      {:error, reason} when reason in [:invitation_required, :signup_closed] ->
        conn
        |> put_flash_t(:error, signup_refused(reason))
        |> redirect(to: ~p"/registration/new")

      {:error, :email_unavailable} ->
        conn
        |> put_flash_t(:error, "flash.email_unavailable")
        |> redirect(to: ~p"/registration/new")

      {:error, changeset} ->
        conn |> assign_changeset_errors(changeset) |> redirect(to: ~p"/registration/new")
    end
  end

  defp signup_refused(:invitation_required), do: "flash.invitation_required"
  defp signup_refused(:signup_closed), do: "flash.signup_closed"
end
