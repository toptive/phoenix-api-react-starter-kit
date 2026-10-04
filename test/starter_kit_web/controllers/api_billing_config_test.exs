defmodule StarterKitWeb.ApiBillingConfigTest do
  use StarterKitWeb.ConnCase, async: false
  import StarterKitWeb.ApiHelpers
  alias StarterKit.{Accounts, Billing}

  setup %{conn: conn} do
    original = Application.get_env(:starter_kit, Billing)
    on_exit(fn -> Application.put_env(:starter_kit, Billing, original) end)
    conn = api_conn(conn)
    scope = scope_fixture(superadmin_fixture())

    %{
      conn: conn,
      auth: bearer(conn, Accounts.generate_api_token(scope.user).token),
      scope: scope,
      original: original
    }
  end

  test "template off with no keys: checkout and webhook return 404", %{
    conn: conn,
    auth: auth,
    original: original
  } do
    put_flag(:billing, false)
    configure(original, secret_key: nil, webhook_secret: nil)
    assert_error(post(auth, ~p"/api/v1/settings/billing/checkout-session", %{}), 404, "not_found")
    assert_error(post(conn, ~p"/webhooks/stripe/events", "{}"), 404, "not_found")

    assert json_response(get(conn, ~p"/api/v1/bootstrap"), 200)["data"]["flags"] == %{
             "billing" => false
           }
  end

  test "missing and wrong-mode keys and missing price refuse before Stripe", %{
    auth: auth,
    original: original,
    scope: scope
  } do
    Req.Test.stub(Billing.Stripe, fn _ -> flunk("Stripe must not be called") end)

    for config <- [[secret_key: nil], [mode: :live, secret_key: "sk_test_fake"], [prices: %{}]] do
      configure(original, config)

      assert_error(
        post(auth, ~p"/api/v1/settings/billing/checkout-session", checkout()),
        503,
        "stripe_unavailable"
      )
    end

    subscription_fixture(scope)
    configure(original, secret_key: nil)

    assert_error(
      post(auth, ~p"/api/v1/settings/billing/portal-session", %{}),
      503,
      "stripe_unavailable"
    )
  end

  test "listed test operator can check out, live prices and revision come from config", %{
    conn: conn,
    original: original
  } do
    scope = scope_fixture()
    auth = bearer(conn, Accounts.generate_api_token(scope.user).token)
    configure(original, test_operator_user_ids: [scope.user.id])

    Req.Test.stub(Billing.Stripe, fn conn ->
      if conn.method == "GET",
        do:
          Req.Test.json(conn, %{
            active: true,
            livemode: false,
            unit_amount: 1900,
            currency: "usd",
            recurring: %{interval: "month"}
          }),
        else: Req.Test.json(conn, %{url: "https://checkout.stripe.com/c/pay/test"})
    end)

    assert json_response(post(auth, ~p"/api/v1/settings/billing/checkout-session", checkout()), 201)[
             "data"
           ]["url"]

    first = json_response(get(auth, ~p"/api/v1/settings/billing"), 200)["data"]
    [monthly | rest] = original[:offers]

    configure(original,
      mode: :live,
      secret_key: "sk_live_fake",
      offers: [%{monthly | amount_cents: 2900} | rest]
    )

    current = json_response(get(auth, ~p"/api/v1/settings/billing"), 200)["data"]
    assert current["sales"] == %{"status" => "open", "testMode" => false}
    assert hd(current["offers"])["amountCents"] == 2900
    refute current["offerRevision"] == first["offerRevision"]
  end

  defp checkout,
    do: %{offerId: "pro_monthly", offerRevision: Billing.offer_revision(), accepted: true}

  defp configure(original, changes),
    do: Application.put_env(:starter_kit, Billing, Keyword.merge(original, changes))
end
