defmodule StarterKitWeb.Api.V1.Auth.PasswordResetController do
  @moduledoc "Private reset requests and single-use password resets."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts
  alias StarterKitWeb.ApiAuth
  plug StarterKitWeb.Plugs.RateLimit, bucket: "api_password_reset", limit: 5, period: 60_000

  def create(conn, %{"email" => email}) do
    conn = skip_authorization(conn)

    if is_binary(email) do
      case Accounts.deliver_password_reset(email, &ApiAuth.spa_url("/auth/password-resets/#{&1}")) do
        :ok -> render_data(conn, nil)
        {:error, reason} -> ApiAuth.error(conn, reason)
      end
    else
      render_error(conn, 400, :bad_request)
    end
  end

  def create(conn, _params), do: conn |> skip_authorization() |> render_error(400, :bad_request)

  def update(conn, %{"token" => token} = params) do
    conn = skip_authorization(conn)

    case Accounts.reset_api_password(token, params) do
      {:ok, _user} -> render_data(conn, nil)
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end
end
