defmodule StarterKitWeb.EmailOptOutController do
  @moduledoc """
  One-click unsubscribe from optional mail (RFC 8058), no sign-in needed: the signed
  token in the URL names the user.

  `show` is the page behind the footer link: one button, so link scanners that only GET
  never unsubscribe anyone. `create` is the button and the `List-Unsubscribe` target:
  mail clients POST `List-Unsubscribe=One-Click` with no session or CSRF token and get
  a bare 200. It is idempotent; a token that names nobody gets 404.
  """
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.Accounts

  page "email-opt-out/show", props: [token: :string, email: :string, subscribed: :boolean]

  # Mail providers POST from shared IPs: a generous limit, JSON on deny (no session here).
  plug StarterKitWeb.Plugs.RateLimit,
       [bucket: "email_opt_out", limit: 120, period: 60_000, format: :json]
       when action == :create

  def show(conn, %{"token" => token}) do
    conn = skip_authorization(conn)

    case Accounts.get_user_by_unsubscribe_token(token) do
      {:ok, user} ->
        render_inertia(conn, "email-opt-out/show", %{
          token: token,
          email: user.email,
          subscribed: user.optional_emails
        })

      :error ->
        conn |> put_flash_t(:error, "flash.email_opt_out_invalid") |> redirect(to: ~p"/")
    end
  end

  def create(conn, %{"token" => token} = params) do
    conn = skip_authorization(conn)
    result = Accounts.unsubscribe_from_optional_emails(token)

    cond do
      params["List-Unsubscribe"] == "One-Click" and result == :ok ->
        send_resp(conn, 200, "")

      result == :ok ->
        conn |> put_status(303) |> redirect(to: ~p"/email-subscriptions/#{token}/opt-out")

      true ->
        send_resp(conn, 404, "")
    end
  end
end
