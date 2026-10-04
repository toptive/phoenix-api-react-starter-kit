defmodule StarterKitWeb.Api.V1.EmailOptOutController do
  @moduledoc "Idempotent RFC 8058 and JSON optional-email opt-out."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts
  alias StarterKitWeb.ApiAuth
  plug StarterKitWeb.Plugs.RateLimit, bucket: "api_email_opt_out", limit: 120, period: 60_000

  def create(conn, %{"token" => token}) do
    conn = skip_authorization(conn)

    case Accounts.opt_out_email_subscription(token) do
      {:ok, subscription} ->
        if Enum.any?(
             get_req_header(conn, "content-type"),
             &String.starts_with?(&1, "application/x-www-form-urlencoded")
           ),
           do: send_resp(conn, 200, ""),
           else: render_data(conn, {Serializers.EmailSubscriptionSerializer, subscription})

      {:error, reason} ->
        ApiAuth.error(conn, reason)
    end
  end
end
