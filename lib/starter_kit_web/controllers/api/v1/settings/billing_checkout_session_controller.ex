defmodule StarterKitWeb.Api.V1.Settings.BillingCheckoutSessionController do
  @moduledoc "Creates a Stripe checkout session with server-owned offer terms."
  use StarterKitWeb, :controller
  alias StarterKit.Billing
  alias StarterKitWeb.{ApiAuth, BillingResponses}
  plug :require_billing

  def create(conn, params) do
    conn = authorize!(conn, :manage_billing, scope(conn).organization)

    urls = %{
      success_url: ApiAuth.spa_url("/settings/billing?checkout=done"),
      cancel_url: ApiAuth.spa_url("/settings/billing")
    }

    case Billing.create_checkout_session(
           scope(conn),
           Map.take(params, ["offer_id", "offer_revision", "accepted"]),
           urls
         ) do
      {:ok, url} ->
        conn |> put_status(201) |> render_data({Serializers.RedirectUrlSerializer, %{url: url}})

      {:error, reason} ->
        BillingResponses.error(conn, reason)
    end
  end

  defp require_billing(conn, _opts) do
    if Billing.enabled?(),
      do: conn,
      else: conn |> skip_authorization() |> render_error(404, :not_found) |> halt()
  end
end
