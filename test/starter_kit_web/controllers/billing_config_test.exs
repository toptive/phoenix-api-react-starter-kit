defmodule StarterKitWeb.BillingConfigTest do
  # Changes the global billing config: not async.
  use StarterKitWeb.ConnCase, async: false

  alias StarterKit.Billing

  setup do
    original = Application.get_env(:starter_kit, Billing)
    on_exit(fn -> Application.put_env(:starter_kit, Billing, original) end)
    Req.Test.stub(Billing.Stripe, fn _conn -> flunk("Stripe must not be called") end)
    %{original: original}
  end

  defp put_billing(original, changes),
    do: Application.put_env(:starter_kit, Billing, Keyword.merge(original, changes))

  defp params,
    do: %{
      "offer_id" => "pro_monthly",
      "offer_revision" => Billing.offer_revision(),
      "accepted" => "true"
    }

  test "the template default (OFF, no keys): checkout and webhook answer 404",
       %{conn: conn, original: original} do
    put_flag(:billing, false)
    put_billing(original, secret_key: nil, webhook_secret: nil)
    %{conn: signed_in} = register_and_log_in_superadmin(%{conn: conn})

    assert signed_in |> post(~p"/settings/billing/checkout-session", %{}) |> Map.get(:status) == 404

    assert conn
           |> put_req_header("content-type", "application/json")
           |> post(~p"/webhooks/stripe/events", "{}")
           |> json_response(404)
  end

  test "sales OFF: checkout refused, but webhooks are still reconciled" do
    put_flag(:billing, false)
    scope = scope_fixture()

    Req.Test.stub(Billing.Stripe, fn conn ->
      Req.Test.json(conn, %{
        "id" => "sub_off",
        "livemode" => false,
        "customer" => "cus_off",
        "status" => "canceled",
        "metadata" => %{"organization_id" => scope.organization.id},
        "items" => %{"data" => [%{"price" => %{"id" => "price_test_monthly"}}]}
      })
    end)

    body =
      Jason.encode!(%{
        "id" => "evt_off",
        "type" => "customer.subscription.deleted",
        "livemode" => false,
        "data" => %{"object" => %{"id" => "sub_off"}}
      })

    assert {:ok, _} = Billing.receive_event(body, Billing.Webhook.sign(body, "whsec_test_fake"))
    assert Billing.current_subscription(scope).status == "canceled"

    assert {:error, :disabled} =
             Billing.create_checkout_session(scope_fixture(superadmin_fixture()), params(), %{})
  end

  test "OFF: no limits at all, but a customer can still open the portal to cancel" do
    put_flag(:billing, false)
    scope = scope_fixture()
    subscription_fixture(scope, status: "canceled")
    assert Billing.limit(scope, :members) == :unlimited

    Req.Test.stub(Billing.Stripe, &Req.Test.json(&1, %{"url" => "https://billing.stripe.com/p/1"}))
    assert {:ok, _url} = Billing.create_portal_session(scope, "https://x")
  end

  test "live mode with a test key counts as not configured", %{original: original} do
    put_billing(original, mode: :live, secret_key: "sk_test_fake")

    assert {:error, :not_configured} =
             Billing.create_checkout_session(scope_fixture(superadmin_fixture()), params(), %{})
  end

  test "test mode: a listed operator may check out without being a superadmin",
       %{original: original} do
    scope = scope_fixture()
    put_billing(original, test_operator_user_ids: [scope.user.id], prices: %{})

    # Past the operator check: it stops at the missing price id, before any Stripe call.
    assert {:error, :not_configured} = Billing.create_checkout_session(scope, params(), %{})
    assert {:error, :test_mode} = Billing.create_checkout_session(scope_fixture(), params(), %{})
  end

  test "the billing page: 404 while OFF, unless the organization has a subscription",
       %{conn: conn} do
    put_flag(:billing, false)
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})

    assert conn |> get(~p"/settings/billing") |> Map.get(:status) == 404

    subscription_fixture(scope_fixture(user), status: "canceled")
    props = conn |> get(~p"/settings/billing") |> inertia_props()

    assert %{plan: "free", sales: :closed, subscription: %{"status" => "canceled"}} = props
  end

  test "live mode with a live key: sales are open to every customer", %{original: original} do
    put_billing(original, mode: :live, secret_key: "sk_live_fake")
    assert Billing.sales(scope_fixture().user) == :open
  end

  test "the offer revision changes with any offer term", %{original: original} do
    before = Billing.offer_revision()
    [monthly | rest] = original[:offers]
    put_billing(original, offers: [%{monthly | amount_cents: 2_900} | rest])

    refute Billing.offer_revision() == before
  end
end
