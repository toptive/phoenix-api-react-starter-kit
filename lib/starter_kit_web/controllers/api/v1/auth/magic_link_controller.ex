defmodule StarterKitWeb.Api.V1.Auth.MagicLinkController do
  @moduledoc "Requests a magic link without revealing whether an account exists."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts
  alias StarterKitWeb.ApiAuth

  plug StarterKitWeb.Plugs.RateLimit,
       [limit: 5, period: 60_000, bucket: "api_magic_link"] when action == :create

  plug StarterKitWeb.Plugs.VerifyTurnstile, "magic_link" when action == :create

  def create(conn, %{"email" => email}) do
    conn = skip_authorization(conn)

    if is_binary(email) do
      case Accounts.deliver_login_instructions(email, &ApiAuth.spa_url("/magic-links/#{&1}")) do
        :ok ->
          conn
          |> put_status(202)
          |> render_data(
            {Serializers.MagicLinkRequestSerializer, %{email: email, new_account: false}}
          )

        {:error, reason} ->
          ApiAuth.error(conn, reason)
      end
    else
      render_error(conn, 400, :bad_request)
    end
  end

  def create(conn, _params), do: conn |> skip_authorization() |> render_error(400, :bad_request)

  def show(conn, %{"token" => token}) do
    conn = skip_authorization(conn)

    case Accounts.peek_magic_link(token) do
      {:ok, preview} -> render_data(conn, {Serializers.MagicLinkSerializer, preview})
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end
end
