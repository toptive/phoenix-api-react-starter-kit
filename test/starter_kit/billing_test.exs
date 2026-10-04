defmodule StarterKit.BillingTest do
  use StarterKit.DataCase, async: true

  alias StarterKit.Audit.AuditEvent
  alias StarterKit.Billing
  alias StarterKit.Billing.Webhook

  @urls %{success_url: "https://app.example.com/done", cancel_url: "https://app.example.com/back"}
  @checkout_url "https://checkout.stripe.com/c/pay/cs_test_1"

  @monthly_price %{
    "id" => "price_test_monthly",
    "active" => true,
    "livemode" => false,
    "unit_amount" => 1_900,
    "currency" => "usd",
    "recurring" => %{"interval" => "month"}
  }

  # Answers like Stripe and reports every request to the test process.
  defp stub_stripe(price \\ @monthly_price, session \\ {200, %{"url" => @checkout_url}}) do
    test = self()

    Req.Test.stub(Billing.Stripe, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        test,
        {:stripe, conn.method, conn.request_path, URI.decode_query(body), conn.req_headers}
      )

      case {conn.method, conn.request_path} do
        {"GET", "/v1/prices/" <> _} ->
          Req.Test.json(conn, price)

        {"POST", "/v1/checkout/sessions"} ->
          {status, json} = session
          conn |> Plug.Conn.put_status(status) |> Req.Test.json(json)
      end
    end)
  end

  defp stub_no_stripe do
    Req.Test.stub(Billing.Stripe, fn _conn -> flunk("Stripe must not be called") end)
  end

  defp params(overrides \\ %{}) do
    Map.merge(
      %{
        "offer_id" => "pro_monthly",
        "offer_revision" => Billing.offer_revision(),
        "accepted" => "true"
      },
      overrides
    )
  end

  defp operator_scope, do: scope_fixture(superadmin_fixture())

  describe "offers" do
    test "come from config with the currency filled in" do
      assert [%{id: "pro_monthly", amount_cents: 1_900, currency: "usd"}, %{id: "pro_yearly"}] =
               Billing.list_offers()

      assert Billing.offer_revision() =~ ~r/^[\w-]{16}$/
    end
  end

  test "no copy mentions tax: the shown price is the price charged" do
    for [key | texts] <- "i18n/translations.csv" |> File.read!() |> NimbleCSV.RFC4180.parse_string(),
        text <- texts do
      refute text =~ ~r/\b(tax|taxes|VAT|GST|impuestos?|IVA)\b/i, "#{key} mentions tax: #{text}"
    end
  end

  describe "checkout" do
    test "sends the exact offer, never Stripe Tax, never a converted currency" do
      stub_stripe()
      scope = operator_scope()

      assert {:ok, @checkout_url} = Billing.create_checkout_session(scope, params(), @urls)

      assert_received {:stripe, "GET", "/v1/prices/price_test_monthly", _, _}
      assert_received {:stripe, "POST", "/v1/checkout/sessions", form, headers}

      assert form["mode"] == "subscription"
      assert form["line_items[0][price]"] == "price_test_monthly"
      assert form["client_reference_id"] == scope.organization.id
      assert form["adaptive_pricing[enabled]"] == "false"
      assert form["custom_text[submit][message]"] =~ "The price you see is the price you pay"
      refute Enum.any?(Map.keys(form), &String.contains?(&1, "automatic_tax"))
      refute Enum.any?(Map.keys(form), &String.contains?(&1, "tax"))

      assert {"stripe-version", "2025-09-30.clover"} in headers
      assert Enum.any?(headers, fn {k, v} -> k == "idempotency-key" and v =~ "checkout-v1-" end)

      assert Repo.get_by(AuditEvent, action: "billing.checkout_started")

      assert_received {:analytics,
                       %{
                         event: "checkout_started",
                         properties: %{"plan" => "pro", "interval" => "month", "mode" => "test"}
                       }}
    end

    test "refuses before calling Stripe: changed offer, no consent, unknown offer" do
      stub_no_stripe()
      scope = operator_scope()

      assert {:error, :offer_changed} =
               Billing.create_checkout_session(scope, params(%{"offer_revision" => "old"}), @urls)

      assert {:error, :not_accepted} =
               Billing.create_checkout_session(scope, params(%{"accepted" => "false"}), @urls)

      assert {:error, :unknown_offer} =
               Billing.create_checkout_session(scope, params(%{"offer_id" => "gold"}), @urls)
    end

    test "test mode: only operators (superadmins, listed ids) may check out" do
      stub_no_stripe()

      assert {:error, :test_mode} =
               Billing.create_checkout_session(scope_fixture(), params(), @urls)
    end

    test "a paid organization changes its plan in the portal, never buys twice" do
      stub_no_stripe()
      scope = operator_scope()
      subscription_fixture(scope)

      assert {:error, :already_subscribed} =
               Billing.create_checkout_session(scope, params(), @urls)
    end

    test "sales: operators see test checkout, everyone else waits for live mode" do
      assert Billing.sales(operator_scope().user) == :test
      assert Billing.sales(scope_fixture().user) == :closed
    end

    test "a Stripe price that differs from the offer refuses the checkout" do
      for wrong <- [
            %{"unit_amount" => 2_900},
            %{"currency" => "hkd"},
            %{"recurring" => %{"interval" => "year"}},
            %{"active" => false},
            %{"livemode" => true}
          ] do
        stub_stripe(Map.merge(@monthly_price, wrong))

        log =
          ExUnit.CaptureLog.capture_log(fn ->
            assert {:error, :price_mismatch} =
                     Billing.create_checkout_session(operator_scope(), params(), @urls)
          end)

        assert log =~ "does not match the offer"

        refute_received {:stripe, "POST", "/v1/checkout/sessions", _, _}
      end
    end

    test "a Stripe error keeps only type and code (messages can hold customer data)" do
      error = %{
        "error" => %{"type" => "invalid_request_error", "code" => "x", "message" => "a@b.c"}
      }

      stub_stripe(@monthly_price, {400, error})

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:error, {:stripe, 400, details}} =
                   Billing.create_checkout_session(operator_scope(), params(), @urls)

          send(self(), {:details, details})
        end)

      assert_received {:details, details}
      refute log =~ "a@b.c"

      assert details == %{"type" => "invalid_request_error", "code" => "x"}
    end

    test "a session URL outside checkout.stripe.com is refused" do
      stub_stripe(@monthly_price, {200, %{"url" => "https://evil.example/pay"}})

      assert {:error, :unexpected_stripe_url} =
               Billing.create_checkout_session(operator_scope(), params(), @urls)
    end
  end

  describe "plans and limits" do
    test "no subscription: the default plan and its limits" do
      scope = scope_fixture()
      assert Billing.plan(scope) == "free"
      assert Billing.limit(scope, :members) == 3
    end

    test "a paid subscription gives its plan; unlimited is nil in config" do
      scope = scope_fixture()
      subscription_fixture(scope)
      assert Billing.plan(scope) == "pro"
      assert Billing.limit(scope, :members) == :unlimited
    end

    test "past_due keeps the plan while Stripe retries the payment" do
      scope = scope_fixture()
      subscription_fixture(scope, status: "past_due")
      assert Billing.plan(scope) == "pro"
    end

    test "canceled, unpaid, paused, ended or other-mode subscriptions give the default plan" do
      past = DateTime.add(DateTime.utc_now(:second), -1, :day)

      for attrs <- [
            [status: "canceled"],
            [status: "unpaid"],
            [status: "incomplete"],
            [paused: true],
            [current_period_end: past],
            [current_period_end: nil],
            [livemode: true]
          ] do
        scope = scope_fixture()
        subscription_fixture(scope, attrs)
        assert Billing.plan(scope) == "free", "expected free for #{inspect(attrs)}"
      end
    end

    test "a limit key missing from the plan is a programming error" do
      assert_raise ArgumentError, ~r/no limit :projects/, fn ->
        Billing.limit(scope_fixture(), :projects)
      end
    end

    test "with_capacity writes under the limit and refuses at it, without writing" do
      scope = scope_fixture()

      assert {:ok, :written} =
               Billing.with_capacity(scope, :members, fn -> 2 end, fn -> {:ok, :written} end)

      assert {:error, {:limit_reached, :members, 3}} =
               Billing.with_capacity(scope, :members, fn -> 3 end, fn -> flunk("wrote") end)
    end

    test "with_capacity: a paid plan without a limit always writes" do
      scope = scope_fixture()
      subscription_fixture(scope)

      assert {:ok, :written} =
               Billing.with_capacity(scope, :members, fn -> 999 end, fn -> {:ok, :written} end)
    end
  end

  describe "customer portal" do
    test "opens Stripe's portal for the organization's customer" do
      scope = operator_scope()
      sub = subscription_fixture(scope)
      test = self()

      Req.Test.stub(Billing.Stripe, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test, {:portal, conn.request_path, URI.decode_query(body)})
        Req.Test.json(conn, %{"url" => "https://billing.stripe.com/p/session/test_1"})
      end)

      assert {:ok, "https://billing.stripe.com/p/session/test_1"} =
               Billing.create_portal_session(scope, "https://app.example.com/back")

      assert_received {:portal, "/v1/billing_portal/sessions", form}
      assert form["customer"] == sub.stripe_customer_id
      assert form["return_url"] == "https://app.example.com/back"
      assert Repo.get_by(AuditEvent, action: "billing.portal_opened")
    end

    test "without a subscription there is nothing to open (no Stripe call)" do
      stub_no_stripe()

      assert {:error, :no_subscription} =
               Billing.create_portal_session(scope_fixture(), "https://x")
    end

    test "a portal URL outside billing.stripe.com is refused" do
      scope = scope_fixture()
      subscription_fixture(scope)
      Req.Test.stub(Billing.Stripe, &Req.Test.json(&1, %{"url" => "https://evil.example/p"}))

      assert {:error, :unexpected_stripe_url} = Billing.create_portal_session(scope, "https://x")
    end
  end

  describe "webhooks" do
    @secret "whsec_test_fake"

    defp event(livemode \\ false),
      do:
        Jason.encode!(%{
          "id" => "evt_1",
          "type" => "customer.subscription.updated",
          "livemode" => livemode
        })

    test "a correctly signed event is accepted" do
      body = event()

      assert {:ok, "customer.subscription.updated"} =
               Billing.receive_event(body, Webhook.sign(body, @secret))
    end

    test "wrong secret, changed body, stale timestamp, missing header: refused" do
      body = event()
      old = System.system_time(:second) - 301

      assert {:error, :invalid_signature} =
               Billing.receive_event(body, Webhook.sign(body, "whsec_other"))

      assert {:error, :invalid_signature} =
               Billing.receive_event(body <> " ", Webhook.sign(body, @secret))

      assert {:error, :stale_signature} =
               Billing.receive_event(body, Webhook.sign(body, @secret, old))

      assert {:error, :invalid_signature} = Billing.receive_event(body, nil)
      assert {:error, :invalid_signature} = Billing.receive_event(body, "t=1,v0=abc")
    end

    test "any one matching v1 signature is enough (secret rotation)" do
      body = event()
      "t=" <> rest = Webhook.sign(body, @secret)
      [t, v1] = String.split(rest, ",")
      header = "t=#{t},v1=#{String.duplicate("0", 64)},#{v1}"
      assert {:ok, _} = Billing.receive_event(body, header)
    end

    test "a live event never reaches a test-mode deployment" do
      body = event(true)
      assert {:error, :wrong_mode} = Billing.receive_event(body, Webhook.sign(body, @secret))
    end
  end
end
