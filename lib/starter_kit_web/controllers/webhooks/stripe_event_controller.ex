defmodule StarterKitWeb.Webhooks.StripeEventController do
  @moduledoc """
  `POST /webhooks/stripe/events`: Stripe's event notifications. No session and no
  CSRF; the `Stripe-Signature` header over the raw body (`Plugs.RawBody`) is the
  authentication, checked by `Billing.receive_event/2`.

  Answers 200 for a verified event (also a repeated one), 400 for a bad or stale
  signature (Stripe retries), 404 while no webhook secret is configured. It does not
  depend on `BILLING_ENABLED`, so cancellations are recorded even when sales are off.
  """
  use StarterKitWeb, :controller

  alias StarterKit.Billing

  plug StarterKitWeb.Plugs.RateLimit, bucket: "stripe_webhook", limit: 600, period: 60_000

  def create(conn, _params) do
    # Not a user action: the signature check below is the authorization.
    conn = skip_authorization(conn)
    signature = conn |> get_req_header("stripe-signature") |> List.first()

    case Billing.receive_event(conn.assigns[:raw_body] || "", signature) do
      {:ok, _type} -> render_data(conn, %{received: true})
      {:error, :not_configured} -> render_error(conn, 404, :not_found)
      {:error, _reason} -> render_error(conn, 400, :invalid_signature)
    end
  end
end
