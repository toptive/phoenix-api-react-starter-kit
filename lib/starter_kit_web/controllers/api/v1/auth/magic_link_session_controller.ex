defmodule StarterKitWeb.Api.V1.Auth.MagicLinkSessionController do
  @moduledoc "Consumes a magic link by POST so scanners cannot sign the user in."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts
  alias StarterKitWeb.ApiAuth

  plug StarterKitWeb.Plugs.RateLimit, bucket: "api_magic_session", limit: 10, period: 60_000

  def create(conn, %{"token" => token}) do
    conn = skip_authorization(conn)

    ApiAuth.session_result(
      conn,
      Accounts.create_magic_link_session(token, ApiAuth.device(conn)),
      "magic_link"
    )
  end
end
