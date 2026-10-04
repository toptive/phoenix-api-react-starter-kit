defmodule StarterKitWeb.BillingResponses do
  @moduledoc "Stable public codes for billing context refusals; Stripe details stay private."
  alias StarterKitWeb.Responses

  def error(conn, reason) do
    {status, code} =
      case reason do
        reason when reason in [:disabled, :not_found] -> {404, :not_found}
        :test_mode -> {403, :test_mode}
        reason when reason in [:already_subscribed, :no_subscription] -> {409, reason}
        :unknown_offer -> {422, :offer_changed}
        reason when reason in [:offer_changed, :not_accepted, :price_mismatch] -> {422, reason}
        _ -> {503, :stripe_unavailable}
      end

    Responses.render_error(conn, status, code)
  end
end
