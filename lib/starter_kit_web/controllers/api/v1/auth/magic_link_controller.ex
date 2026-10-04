defmodule StarterKitWeb.Api.V1.Auth.MagicLinkController do
  @moduledoc "Requests a magic link without revealing whether an account exists."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts
  alias StarterKitWeb.ApiAuth

  plug StarterKitWeb.Plugs.RateLimit, bucket: "api_magic_link", limit: 5, period: 60_000
  plug StarterKitWeb.Plugs.VerifyTurnstile, "magic_link"

  def create(conn, %{"email" => email}) do
    conn = skip_authorization(conn)

    if is_binary(email) do
      case Accounts.deliver_login_instructions(email, &ApiAuth.spa_url("/auth/magic-links/#{&1}")) do
        :ok -> render_data(conn, nil, %{message: "flash.magic_link_sent"})
        {:error, reason} -> ApiAuth.error(conn, reason)
      end
    else
      render_error(conn, 400, :bad_request)
    end
  end

  def create(conn, _params), do: conn |> skip_authorization() |> render_error(400, :bad_request)
end
