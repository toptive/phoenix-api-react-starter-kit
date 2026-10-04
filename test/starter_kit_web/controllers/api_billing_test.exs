defmodule StarterKitWeb.ApiBillingTest do
  use StarterKitWeb.ConnCase, async: true
  import StarterKitWeb.ApiHelpers
  import ExUnit.CaptureLog
  alias StarterKit.{Accounts, Billing, Repo}
  alias StarterKit.Audit.AuditEvent
  alias StarterKit.Billing.{Event, Webhook}

  @checkout_url "https://checkout.stripe.com/c/pay/cs_test_1"
  @portal_url "https://billing.stripe.com/p/session/test_1"

  setup %{conn: conn} do
    conn = api_conn(conn)
    scope = scope_fixture(superadmin_fixture())
    token = Accounts.generate_api_token(scope.user).token
    %{conn: conn, scope: scope, auth: bearer(conn, token)}
  end

  for {method, path} <- [
        {:get, "/api/v1/settings/billing"},
        {:post, "/api/v1/settings/billing/checkout-session"},
        {:post, "/api/v1/settings/billing/portal-session"}
      ] do
    @method method
    @path path
    test "#{method} #{path} requires a bearer", %{conn: conn} do
      assert_error(
        Phoenix.ConnTest.dispatch(conn, @endpoint, @method, @path, %{}),
        401,
        "unauthorized"
      )
    end
  end

  test "overview returns the complete contract, configured prices, no Stripe ids and no cookies", %{
    auth: auth
  } do
    result = get(auth, ~p"/api/v1/settings/billing")
    data = json_response(result, 200)["data"]

    assert Map.keys(data) |> Enum.sort() ==
             ~w(canManage offerRevision offers plan sales subscription)

    assert data["plan"] == "free" and data["subscription"] == nil and data["canManage"]
    assert data["sales"] == "test"
    assert data["offerRevision"] == Billing.offer_revision()

    assert [
             %{
               "id" => "pro_monthly",
               "amountCents" => 1900,
               "currency" => "usd",
               "interval" => "month"
             },
             %{"id" => "pro_yearly", "amountCents" => 19_000}
           ] = data["offers"]

    assert get_resp_header(result, "cache-control") == ["private, no-store"]
    assert get_resp_header(result, "set-cookie") == []
  end

  test "members and viewers can see prices but cannot buy or manage payments", %{
    conn: conn,
    scope: owner
  } do
    for {role, access} <- [{:member, :full}, {:admin, :viewer}] do
      user = user_fixture()
      membership_fixture(owner, user, role, access)

      auth =
        bearer(
          conn,
          Accounts.generate_api_token(user, %{}, organization_id: owner.organization.id).token
        )

      data = json_response(get(auth, ~p"/api/v1/settings/billing"), 200)["data"]
      refute data["canManage"]
      assert data["sales"] == "closed"

      for path <- [
            "/api/v1/settings/billing/checkout-session",
            "/api/v1/settings/billing/portal-session"
          ],
          do: assert_error(post(auth, path, checkout()), 403, "forbidden")
    end
  end

  test "billing off → 404; on → overview → checkout → signed paid webhook → paid overview", %{
    conn: conn,
    auth: auth,
    scope: scope
  } do
    put_flag(:billing, false)
    assert_error(get(auth, ~p"/api/v1/settings/billing"), 404, "not_found")

    assert_error(
      post(auth, ~p"/api/v1/settings/billing/checkout-session", checkout()),
      404,
      "not_found"
    )

    put_flag(:billing, true)
    overview = json_response(get(auth, ~p"/api/v1/settings/billing"), 200)["data"]
    stub_stripe(scope)

    result =
      post(auth, ~p"/api/v1/settings/billing/checkout-session", %{
        offerId: "pro_monthly",
        offerRevision: overview["offerRevision"],
        accepted: "true"
      })

    assert json_response(result, 201)["data"] == %{"url" => @checkout_url}
    assert get_resp_header(result, "set-cookie") == []
    assert_received {:checkout_form, form, [idempotency]}
    assert form["success_url"] == "http://localhost:5173/settings/billing?checkout=done"
    assert form["cancel_url"] == "http://localhost:5173/settings/billing"
    assert form["allow_promotion_codes"] == "true"
    assert form["adaptive_pricing[enabled]"] == "false"
    assert form["custom_text[submit][message]"] == StarterKit.I18n.t("billing.price_note")
    assert form["metadata[organization_id]"] == scope.organization.id
    assert form["subscription_data[metadata][organization_id]"] == scope.organization.id
    refute Enum.any?(Map.keys(form), &String.contains?(&1, "tax"))
    assert idempotency =~ "#{scope.organization.id}-#{scope.user.id}-pro_monthly"
    post(auth, ~p"/api/v1/settings/billing/checkout-session", checkout()) |> json_response(201)
    assert_received {:checkout_form, _, [^idempotency]}
    Repo.update!(Ecto.Changeset.change(scope.user, locale: "es"))
    post(auth, ~p"/api/v1/settings/billing/checkout-session", checkout()) |> json_response(201)
    assert_received {:checkout_form, localized, [localized_key]}
    assert localized_key != idempotency
    assert localized_key =~ "-es-"

    assert localized["custom_text[submit][message]"] ==
             StarterKit.I18n.t("billing.price_note", %{}, "es")

    assert_received {:analytics,
                     %{
                       event: "checkout_started",
                       properties: %{"plan" => "pro", "interval" => "month", "mode" => "test"}
                     }}

    body =
      event_body("checkout.session.completed", %{
        "subscription" => "sub_1",
        "client_reference_id" => scope.organization.id
      })

    assert json_response(deliver(conn, body), 200) == %{"received" => true}
    assert_received {:subscription_fetch, "sub_1"}
    data = json_response(get(auth, ~p"/api/v1/settings/billing"), 200)["data"]
    assert data["plan"] == "pro"

    assert %{
             "paid" => true,
             "status" => "active",
             "offerId" => "pro_monthly",
             "cancelAtPeriodEnd" => false,
             "paused" => false
           } = data["subscription"]

    refute inspect(data) =~ "cus_"
    refute inspect(data) =~ "sub_1"

    assert_received {:analytics,
                     %{
                       event: "subscription_started",
                       properties: %{"$process_person_profile" => false}
                     }}

    assert Repo.get_by!(AuditEvent, action: "billing.subscription_changed").organization_id ==
             scope.organization.id

    assert_error(
      post(auth, ~p"/api/v1/settings/billing/checkout-session", checkout()),
      409,
      "already_subscribed"
    )

    assert json_response(deliver(conn, body), 200) == %{"received" => true}
    refute_received {:subscription_fetch, _}
    assert Repo.aggregate(Event, :count) == 1
    put_flag(:billing, false)

    assert json_response(get(auth, ~p"/api/v1/settings/billing"), 200)["data"]["sales"] ==
             "closed"

    assert json_response(post(auth, ~p"/api/v1/settings/billing/portal-session", %{}), 201)["data"] ==
             %{"url" => @portal_url}

    assert_received {:portal_form, portal}
    assert portal["return_url"] == "http://localhost:5173/settings/billing"
    assert portal["customer"] == "cus_1"
    assert Repo.get_by!(AuditEvent, action: "billing.portal_opened")
  end

  test "overview and portal use the bearer tenant, ignoring another organization's hints", %{
    auth: auth,
    scope: scope
  } do
    other = scope_fixture()
    subscription_fixture(other)

    assert json_response(
             get(auth, ~p"/api/v1/settings/billing?organizationId=#{other.organization.id}"),
             200
           )["data"]["subscription"] == nil

    assert_error(
      post(auth, ~p"/api/v1/settings/billing/portal-session", %{
        organizationId: other.organization.id
      }),
      409,
      "no_subscription"
    )

    subscription_fixture(scope, status: "canceled")
    data = json_response(get(auth, ~p"/api/v1/settings/billing"), 200)["data"]
    assert data["plan"] == "free" and data["subscription"]["status"] == "canceled"
  end

  test "checkout refuses a non-operator, unknown/stale offer and missing acceptance before HTTP", %{
    auth: auth,
    conn: conn
  } do
    Req.Test.stub(Billing.Stripe, fn _ -> flunk("Stripe must not be called") end)
    ordinary = bearer(conn, Accounts.generate_api_token(user_fixture()).token)

    assert_error(
      post(ordinary, ~p"/api/v1/settings/billing/checkout-session", checkout()),
      403,
      "test_mode"
    )

    for params <- [
          Map.put(checkout(), :offerId, "unknown"),
          Map.put(checkout(), :offerRevision, "stale"),
          %{}
        ] do
      assert_error(
        post(auth, ~p"/api/v1/settings/billing/checkout-session", params),
        422,
        "offer_changed"
      )
    end

    assert_error(
      post(
        auth,
        ~p"/api/v1/settings/billing/checkout-session",
        Map.put(checkout(), :accepted, false)
      ),
      422,
      "not_accepted"
    )

    refute Repo.get_by(AuditEvent, action: "billing.checkout_started")
  end

  test "Stripe price amount, currency, interval, active and mode must all match", %{auth: auth} do
    for change <- [
          %{"unit_amount" => 2900},
          %{"currency" => "eur"},
          %{"recurring" => %{"interval" => "year"}},
          %{"active" => false},
          %{"livemode" => true}
        ] do
      Req.Test.stub(Billing.Stripe, fn conn ->
        assert conn.request_path == "/v1/prices/price_test_monthly"
        Req.Test.json(conn, Map.merge(price(), change))
      end)

      capture_log(fn ->
        assert_error(
          post(auth, ~p"/api/v1/settings/billing/checkout-session", checkout()),
          422,
          "price_mismatch"
        )
      end)
    end

    refute Repo.get_by(AuditEvent, action: "billing.checkout_started")
  end

  test "Stripe HTTP errors and unsafe destinations are translated without provider details", %{
    auth: auth,
    scope: scope
  } do
    subscription_fixture(scope)

    for path <- [
          "/api/v1/settings/billing/checkout-session",
          "/api/v1/settings/billing/portal-session"
        ] do
      if String.ends_with?(path, "checkout-session"),
        do: Repo.delete_all(Billing.Subscription, org_id: scope.organization.id)

      Req.Test.stub(
        Billing.Stripe,
        &(&1 |> put_status(500) |> Req.Test.json(%{"error" => %{"message" => "private detail"}}))
      )

      capture_log(fn ->
        result = post(auth, path, checkout())
        assert_error(result, 503, "stripe_unavailable")
        refute result.resp_body =~ "private detail"
      end)

      if String.ends_with?(path, "checkout-session"), do: subscription_fixture(scope)
    end

    Req.Test.stub(Billing.Stripe, &Req.Test.json(&1, %{"url" => "https://evil.example/"}))

    assert_error(
      post(auth, ~p"/api/v1/settings/billing/portal-session", %{}),
      503,
      "stripe_unavailable"
    )
  end

  test "webhook signature covers raw spacing, permits key rotation and refuses changed/stale signatures",
       %{conn: conn} do
    body = ~s({"id":"evt_raw",  "type":"customer.created", "livemode":false})
    signed = Webhook.sign(body, "whsec_test_fake")
    assert json_response(deliver(conn, body, signed <> ",v1=old-key"), 200) == %{"received" => true}

    for signature <- [
          nil,
          "bad",
          Webhook.sign(body, "wrong"),
          Webhook.sign(body, "whsec_test_fake", System.system_time(:second) - 301),
          Webhook.sign(body, "whsec_test_fake", System.system_time(:second) + 301)
        ] do
      assert_error(deliver(conn, body, signature), 400, "invalid_signature")
    end

    assert_error(deliver(conn, body <> " ", signed), 400, "invalid_signature")
    assert Repo.aggregate(Event, :count) == 0
  end

  test "unhandled events are not stored and wrong-mode events are refused", %{conn: conn} do
    assert json_response(deliver(conn, event_body("customer.created", %{})), 200) == %{
             "received" => true
           }

    body = Jason.encode!(%{id: "evt_live", type: "invoice.paid", livemode: true})
    assert_error(deliver(conn, body), 400, "invalid_signature")
    assert Repo.aggregate(Event, :count) == 0
  end

  test "webhooks limit requests to 600 per minute", %{conn: conn} do
    body = event_body("customer.created", %{})
    for _ <- 1..600, do: assert(json_response(deliver(conn, body), 200))
    limited = deliver(conn, body)
    assert_error(limited, 429, "rate_limited")
    assert get_resp_header(limited, "retry-after") != []
  end

  defp checkout,
    do: %{offerId: "pro_monthly", offerRevision: Billing.offer_revision(), accepted: true}

  defp price,
    do: %{
      "active" => true,
      "livemode" => false,
      "unit_amount" => 1900,
      "currency" => "usd",
      "recurring" => %{"interval" => "month"}
    }

  defp stub_stripe(scope) do
    test = self()

    Req.Test.stub(Billing.Stripe, fn conn ->
      case conn.request_path do
        "/v1/prices/" <> _ ->
          Req.Test.json(conn, price())

        "/v1/checkout/sessions" ->
          {:ok, body, conn} = read_body(conn)

          send(
            test,
            {:checkout_form, URI.decode_query(body), get_req_header(conn, "idempotency-key")}
          )

          Req.Test.json(conn, %{url: @checkout_url})

        "/v1/billing_portal/sessions" ->
          {:ok, body, conn} = read_body(conn)
          send(test, {:portal_form, URI.decode_query(body)})
          Req.Test.json(conn, %{url: @portal_url})

        "/v1/subscriptions/" <> id ->
          send(test, {:subscription_fetch, id})

          Req.Test.json(conn, %{
            id: id,
            livemode: false,
            customer: "cus_1",
            status: "active",
            cancel_at_period_end: false,
            metadata: %{organization_id: scope.organization.id},
            items: %{
              data: [
                %{
                  current_period_end:
                    DateTime.utc_now(:second) |> DateTime.add(30, :day) |> DateTime.to_unix(),
                  price: %{id: "price_test_monthly"}
                }
              ]
            }
          })
      end
    end)
  end

  defp event_body(type, object),
    do:
      Jason.encode!(%{
        id: "evt_#{System.unique_integer([:positive])}",
        type: type,
        livemode: false,
        data: %{object: object}
      })

  defp deliver(conn, body, signature \\ :auto) do
    signature = if signature == :auto, do: Webhook.sign(body, "whsec_test_fake"), else: signature
    conn = delete_req_header(conn, "stripe-signature")
    conn = if signature, do: put_req_header(conn, "stripe-signature", signature), else: conn
    post(conn, ~p"/webhooks/stripe/events", body)
  end
end
