defmodule StarterKit.BillingReconciliationTest do
  @moduledoc """
  Webhook → inbox → job → fetch the subscription from Stripe → upsert. Oban runs inline
  in tests, so `receive_event/2` reconciles before it returns.
  """
  use StarterKit.DataCase, async: true

  import ExUnit.CaptureLog

  alias StarterKit.Audit.AuditEvent
  alias StarterKit.Billing
  alias StarterKit.Billing.{Event, Webhook}

  setup do
    %{scope: scope_fixture()}
  end

  defp in_days(days),
    do: DateTime.utc_now(:second) |> DateTime.add(days, :day) |> DateTime.to_unix()

  defp stripe_sub(org_id, overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "sub_1",
        "object" => "subscription",
        "livemode" => false,
        "customer" => "cus_1",
        "status" => "active",
        "cancel_at_period_end" => false,
        "pause_collection" => nil,
        "metadata" => %{"organization_id" => org_id, "offer_id" => "pro_monthly"},
        "items" => %{
          "data" => [
            %{"current_period_end" => in_days(30), "price" => %{"id" => "price_test_monthly"}}
          ]
        }
      },
      overrides
    )
  end

  # Stripe answers GET /v1/subscriptions/:id with `subs[id]`; every call is reported.
  defp stub_subscriptions(subs) do
    test = self()

    Req.Test.stub(Billing.Stripe, fn conn ->
      "/v1/subscriptions/" <> id = conn.request_path
      send(test, {:fetched, id})
      Req.Test.json(conn, Map.fetch!(subs, id))
    end)
  end

  defp deliver(type, object, event_id \\ "evt_#{System.unique_integer([:positive])}") do
    body =
      Jason.encode!(%{
        "id" => event_id,
        "type" => type,
        "livemode" => false,
        "data" => %{"object" => object}
      })

    Billing.receive_event(body, Webhook.sign(body, "whsec_test_fake"))
  end

  test "checkout completed: the subscription is fetched and stored", %{scope: scope} do
    stub_subscriptions(%{"sub_1" => stripe_sub(scope.organization.id)})

    assert {:ok, "checkout.session.completed"} =
             deliver("checkout.session.completed", %{
               "subscription" => "sub_1",
               "client_reference_id" => scope.organization.id
             })

    sub = Billing.current_subscription(scope)

    assert %{plan: "pro", status: "active", stripe_customer_id: "cus_1", offer_id: "pro_monthly"} =
             sub

    assert Billing.plan(scope) == "pro"
    assert Repo.get_by!(Event, stripe_subscription_id: "sub_1").outcome == "synced"

    assert Repo.get_by(AuditEvent,
             action: "billing.subscription_synced",
             organization_id: scope.organization.id
           )
  end

  test "the revenue funnel: started once when paying begins, canceled when it ends",
       %{scope: scope} do
    org = scope.organization.id
    stub_subscriptions(%{"sub_1" => stripe_sub(org)})
    deliver("customer.subscription.created", %{"id" => "sub_1"})

    assert_received {:analytics,
                     %{
                       event: "subscription_started",
                       properties: %{"plan" => "pro", "interval" => "month", "mode" => "test"}
                     }}

    deliver("customer.subscription.updated", %{"id" => "sub_1"})
    refute_received {:analytics, %{event: "subscription_started"}}

    stub_subscriptions(%{"sub_1" => stripe_sub(org, %{"status" => "canceled"})})
    deliver("customer.subscription.deleted", %{"id" => "sub_1"})
    assert_received {:analytics, %{event: "subscription_canceled"}}
  end

  test "the payload is never trusted: Stripe's own answer wins", %{scope: scope} do
    stub_subscriptions(%{"sub_1" => stripe_sub(scope.organization.id, %{"status" => "canceled"})})

    deliver("customer.subscription.updated", %{"id" => "sub_1", "status" => "active"})

    assert Billing.current_subscription(scope).status == "canceled"
    assert Billing.plan(scope) == "free"
  end

  test "a repeated delivery is processed once", %{scope: scope} do
    stub_subscriptions(%{"sub_1" => stripe_sub(scope.organization.id)})

    assert {:ok, _} = deliver("customer.subscription.updated", %{"id" => "sub_1"}, "evt_same")
    assert {:ok, _} = deliver("customer.subscription.updated", %{"id" => "sub_1"}, "evt_same")

    assert_received {:fetched, "sub_1"}
    refute_received {:fetched, "sub_1"}
    assert Repo.aggregate(Event, :count) == 1
  end

  test "updates replace the row; the period end comes from the subscription item", %{scope: scope} do
    org = scope.organization.id
    stub_subscriptions(%{"sub_1" => stripe_sub(org)})
    deliver("customer.subscription.created", %{"id" => "sub_1"})

    ending = in_days(3)

    stub_subscriptions(%{
      "sub_1" =>
        stripe_sub(org, %{
          "cancel_at_period_end" => true,
          "items" => %{
            "data" => [%{"current_period_end" => ending, "price" => %{"id" => "price_test_yearly"}}]
          }
        })
    })

    deliver("customer.subscription.updated", %{"id" => "sub_1"})

    sub = Billing.current_subscription(scope)
    assert sub.cancel_at_period_end
    assert sub.offer_id == "pro_yearly"
    assert DateTime.to_unix(sub.current_period_end) == ending
    assert Repo.aggregate(StarterKit.Billing.Subscription, :count, org_id: org) == 1
  end

  test "an old subscription's late event never replaces a newer paid one", %{scope: scope} do
    org = scope.organization.id

    stub_subscriptions(%{
      "sub_new" => stripe_sub(org, %{"id" => "sub_new"}),
      "sub_old" => stripe_sub(org, %{"id" => "sub_old", "status" => "canceled"})
    })

    deliver("customer.subscription.created", %{"id" => "sub_new"})
    deliver("customer.subscription.deleted", %{"id" => "sub_old"})

    assert Billing.current_subscription(scope).stripe_subscription_id == "sub_new"
    assert Billing.plan(scope) == "pro"

    assert Repo.get_by!(Event, stripe_subscription_id: "sub_old").outcome ==
             "kept_paid_subscription"
  end

  test "a paused collection gives no paid plan", %{scope: scope} do
    paused = stripe_sub(scope.organization.id, %{"pause_collection" => %{"behavior" => "void"}})
    stub_subscriptions(%{"sub_1" => paused})

    deliver("customer.subscription.paused", %{"id" => "sub_1"})

    assert Billing.current_subscription(scope).paused
    assert Billing.plan(scope) == "free"
  end

  test "invoices find their subscription under parent.subscription_details", %{scope: scope} do
    stub_subscriptions(%{"sub_1" => stripe_sub(scope.organization.id)})

    deliver("invoice.paid", %{
      "parent" => %{"subscription_details" => %{"subscription" => "sub_1", "metadata" => %{}}}
    })

    assert_received {:fetched, "sub_1"}
    assert Billing.plan(scope) == "pro"
  end

  test "an unknown price never gives a paid plan by guess", %{scope: scope} do
    unknown = %{
      "data" => [%{"current_period_end" => in_days(30), "price" => %{"id" => "price_other"}}]
    }

    stub_subscriptions(%{"sub_1" => stripe_sub(scope.organization.id, %{"items" => unknown})})

    log = capture_log(fn -> deliver("customer.subscription.created", %{"id" => "sub_1"}) end)

    assert log =~ "matches no offer"
    assert Billing.plan(scope) == "free"
  end

  test "no organization (no metadata, unknown id): nothing is stored" do
    stub_subscriptions(%{
      "sub_1" => stripe_sub(nil, %{"metadata" => %{}}),
      "sub_2" => stripe_sub(Ecto.UUID.generate())
    })

    deliver("customer.subscription.created", %{"id" => "sub_1"})
    deliver("customer.subscription.created", %{"id" => "sub_2"})

    assert Repo.aggregate(StarterKit.Billing.Subscription, :count, skip_org_id: true) == 0
    assert Repo.get_by!(Event, stripe_subscription_id: "sub_1").outcome == "unknown_organization"
    assert Repo.get_by!(Event, stripe_subscription_id: "sub_2").outcome == "unknown_organization"
  end

  test "events that cannot change a subscription are acknowledged, not stored" do
    Req.Test.stub(Billing.Stripe, fn _conn -> flunk("Stripe must not be called") end)
    assert {:ok, "customer.created"} = deliver("customer.created", %{"id" => "cus_1"})
    assert Repo.aggregate(Event, :count) == 0
  end

  test "a Stripe failure leaves the event for a retry", %{scope: scope} do
    Req.Test.stub(Billing.Stripe, &(&1 |> Plug.Conn.put_status(500) |> Req.Test.json(%{})))

    capture_log(fn -> deliver("customer.subscription.updated", %{"id" => "sub_1"}) end)

    event = Repo.get_by!(Event, stripe_subscription_id: "sub_1")
    assert is_nil(event.processed_at)

    stub_subscriptions(%{"sub_1" => stripe_sub(scope.organization.id)})
    assert :ok = Billing.process_event(event.id)
    assert Billing.plan(scope) == "pro"
  end
end
