defmodule StarterKitWeb.BillingTest do
  use StarterKitWeb.ConnCase, async: true

  alias StarterKit.Billing
  alias StarterKit.Billing.Webhook

  @checkout_url "https://checkout.stripe.com/c/pay/cs_test_1"

  defp stub_stripe do
    Req.Test.stub(Billing.Stripe, fn conn ->
      case conn.request_path do
        "/v1/prices/" <> _ ->
          Req.Test.json(conn, %{
            "active" => true,
            "livemode" => false,
            "unit_amount" => 1_900,
            "currency" => "usd",
            "recurring" => %{"interval" => "month"}
          })

        "/v1/checkout/sessions" ->
          Req.Test.json(conn, %{"url" => @checkout_url})
      end
    end)
  end

  defp checkout(revision \\ Billing.offer_revision()),
    do: %{
      "checkout" => %{"offerId" => "pro_monthly", "offerRevision" => revision, "accepted" => true}
    }

  describe "GET /settings/billing" do
    test "the owner sees the plan, the offers and the revision to send back", %{conn: conn} do
      %{conn: conn} = register_and_log_in_superadmin(%{conn: conn})
      page = get(conn, ~p"/settings/billing")

      assert inertia_component(page) == "settings/billing/show"
      props = inertia_props(page)
      assert %{plan: "free", subscription: nil, canManage: true, fromCheckout: false} = props
      assert props.sales == :test
      assert props.offerRevision == Billing.offer_revision()

      assert [
               %{
                 "id" => "pro_monthly",
                 "amountCents" => 1_900,
                 "currency" => "usd",
                 "interval" => "month"
               }
               | _
             ] =
               props.offers
    end

    test "a paying organization sees its subscription, never a Stripe id", %{conn: conn} do
      %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
      subscription_fixture(scope_fixture(user))

      props = conn |> get(~p"/settings/billing?checkout=done") |> inertia_props()

      assert %{plan: "pro", fromCheckout: true, sales: :closed} = props

      assert %{"paid" => true, "status" => "active", "offerId" => "pro_monthly"} =
               props.subscription

      refute inspect(props) =~ "cus_"
    end

    test "a member sees the plan but cannot change it", %{conn: conn} do
      owner_scope = scope_fixture(superadmin_fixture())
      member = user_fixture()
      membership_fixture(owner_scope, member, :member)

      page =
        conn
        |> log_in_user(member)
        |> put_session(:organization_id, owner_scope.organization.id)
        |> get(~p"/settings/billing")

      assert %{canManage: false, plan: "free"} = inertia_props(page)
    end
  end

  describe "POST /settings/billing/checkout-session" do
    setup :register_and_log_in_superadmin

    test "an Inertia visit is sent to Stripe Checkout", %{conn: conn} do
      stub_stripe()
      conn = conn |> inertia() |> post(~p"/settings/billing/checkout-session", checkout())

      assert conn.status == 409
      assert get_resp_header(conn, "x-inertia-location") == [@checkout_url]
    end

    test "returns to the billing page from Stripe", %{conn: conn} do
      test = self()

      Req.Test.stub(Billing.Stripe, fn conn ->
        if conn.request_path == "/v1/checkout/sessions" do
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(test, {:form, URI.decode_query(body)})
          Req.Test.json(conn, %{"url" => @checkout_url})
        else
          Req.Test.json(conn, %{
            "active" => true,
            "livemode" => false,
            "unit_amount" => 1_900,
            "currency" => "usd",
            "recurring" => %{"interval" => "month"}
          })
        end
      end)

      conn |> inertia() |> post(~p"/settings/billing/checkout-session", checkout())

      assert_received {:form, form}
      assert form["success_url"] == url(~p"/settings/billing?checkout=done")
      assert form["cancel_url"] == url(~p"/settings/billing")
    end

    test "a refused checkout returns with an explanation", %{conn: conn} do
      conn = post(conn, ~p"/settings/billing/checkout-session", checkout("stale"))

      assert redirected_to(conn) == ~p"/settings/billing"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "price changed"
    end
  end

  describe "POST /settings/billing/portal-session" do
    setup :register_and_log_in_user

    test "sends the owner to Stripe's portal", %{conn: conn, user: user} do
      subscription_fixture(scope_fixture(user))
      portal = "https://billing.stripe.com/p/session/test_1"
      Req.Test.stub(Billing.Stripe, &Req.Test.json(&1, %{"url" => portal}))

      conn = conn |> inertia() |> post(~p"/settings/billing/portal-session")
      assert conn.status == 409
      assert get_resp_header(conn, "x-inertia-location") == [portal]
    end

    test "without a subscription: explains and stays", %{conn: conn} do
      conn = post(conn, ~p"/settings/billing/portal-session")
      assert redirected_to(conn) == ~p"/settings/billing"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "no subscription"
    end
  end

  test "a member who does not manage the organization cannot start a checkout", %{conn: conn} do
    owner_scope = scope_fixture(superadmin_fixture())
    member = user_fixture()
    membership_fixture(owner_scope, member, :member)

    conn =
      conn
      |> log_in_user(member)
      |> put_session(:organization_id, owner_scope.organization.id)
      |> post(~p"/settings/billing/checkout-session", checkout())

    assert conn.status == 403
  end

  describe "POST /webhooks/stripe/events" do
    defp post_event(conn, body, signature) do
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("stripe-signature", signature)
      |> post(~p"/webhooks/stripe/events", body)
    end

    test "a signed event is accepted on its raw bytes", %{conn: conn} do
      # Unusual spacing: a re-encoded body would not match the signature.
      body = ~s({"id":"evt_1",  "type":"invoice.paid", "livemode":false})
      conn = post_event(conn, body, Webhook.sign(body, "whsec_test_fake"))

      assert json_response(conn, 200) == %{"data" => %{"received" => true}, "meta" => %{}}
    end

    test "a bad signature is refused with 400", %{conn: conn} do
      body = ~s({"id":"evt_1","type":"invoice.paid","livemode":false})
      conn = post_event(conn, body, Webhook.sign(body, "whsec_wrong"))

      assert %{"error" => %{"code" => "invalid_signature"}} = json_response(conn, 400)
    end
  end
end
