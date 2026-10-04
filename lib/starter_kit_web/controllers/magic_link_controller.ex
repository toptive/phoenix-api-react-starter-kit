defmodule StarterKitWeb.MagicLinkController do
  @moduledoc """
  `create` emails a sign-in link (never reveals whether the email exists).
  `show` is the page behind the link: one button that signs in (POST /session), so
  link scanners that only GET cannot consume the token.
  """
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.Accounts

  page "magic-links/show", props: [token: :string, email: :string, confirmed: :boolean]

  plug StarterKitWeb.Plugs.RateLimit,
       [bucket: "magic_link", limit: 5, period: 60_000] when action == :create

  plug StarterKitWeb.Plugs.VerifyTurnstile, "magic_link" when action == :create

  def create(conn, %{"user" => %{"email" => email}}) do
    conn = skip_authorization(conn)

    case Accounts.deliver_login_instructions(email, &url(~p"/magic-links/#{&1}")) do
      :ok ->
        conn |> put_session(:link_sent_to, email) |> redirect(to: ~p"/session/new")

      {:error, :email_unavailable} ->
        conn |> put_flash_t(:error, "flash.email_unavailable") |> redirect(to: ~p"/session/new")
    end
  end

  def show(conn, %{"token" => token}) do
    conn = skip_authorization(conn)

    case Accounts.get_user_by_magic_link_token(token) do
      nil ->
        conn |> put_flash_t(:error, "flash.magic_link_invalid") |> redirect(to: ~p"/session/new")

      user ->
        render_inertia(conn, "magic-links/show", %{
          token: token,
          email: user.email,
          confirmed: not is_nil(user.confirmed_at)
        })
    end
  end
end
