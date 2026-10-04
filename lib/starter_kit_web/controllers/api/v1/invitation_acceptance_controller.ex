defmodule StarterKitWeb.Api.V1.InvitationAcceptanceController do
  @moduledoc "Accepts an invitation for the signed-in invited address."
  use StarterKitWeb, :controller
  alias StarterKit.{Analytics, Organizations}
  alias StarterKitWeb.ApiAuth
  plug StarterKitWeb.Plugs.RateLimit, bucket: "api_invitation_acceptance", limit: 10, period: 60_000

  def create(conn, %{"token" => token}) do
    conn = authorize!(conn, :show, scope(conn).user)

    case Organizations.accept_invitation(scope(conn), token) do
      {:ok, membership} ->
        Analytics.track("invitation_accepted", scope(conn))
        conn |> put_status(201) |> render_data({Serializers.MembershipSerializer, membership})

      {:error, {:email_mismatch, email}} ->
        render_error(conn, 409, :email_mismatch, %{email: email})

      {:error, reason} ->
        ApiAuth.error(conn, reason)
    end
  end
end
