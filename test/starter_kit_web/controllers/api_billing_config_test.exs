defmodule StarterKitWeb.ApiBillingConfigTest do
  use StarterKitWeb.ConnCase, async: false
  import StarterKitWeb.ApiHelpers
  alias StarterKit.{Accounts, Billing}

  defmodule StripeStub do
    @moduledoc false
    def init(opts), do: opts

    def call(conn, opts) do
      send(opts[:test], {:stub_request, conn.method, conn.request_path})
      url = "http://localhost:#{conn.port}/redirect"

      body =
        if conn.method == "GET" do
          %{
            active: true,
            livemode: false,
            unit_amount: 1900,
            currency: "usd",
            recurring: %{interval: "month"}
          }
        else
          %{url: url}
        end

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(body))
    end
  end

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
    assert current["sales"] == "open"
    assert hd(current["offers"])["amountCents"] == 2900
    refute current["offerRevision"] == first["offerRevision"]
  end

  test "E2E config reaches a local Stripe HTTP stub for checkout and portal", %{
    auth: auth,
    scope: scope
  } do
    pid = start_supervised!({Bandit, plug: {StripeStub, test: self()}, port: 0})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    base = "http://localhost:#{port}/v1/"

    config =
      with_env(
        %{
          "E2E" => "1",
          "E2E_PGDATABASE" => "starter_kit_e2e_config",
          "PORT" => "4100",
          "STRIPE_API_BASE" => base
        },
        fn ->
          Config.Reader.merge(
            Config.Reader.read!("config/config.exs", env: :test),
            Config.Reader.read!("config/runtime.exs", env: :test)
          )
        end
      )

    billing = config[:starter_kit][Billing]
    refute Keyword.has_key?(billing[:req_options], :plug)
    Application.put_env(:starter_kit, Billing, billing)

    assert json_response(post(auth, ~p"/api/v1/settings/billing/checkout-session", checkout()), 201)[
             "data"
           ] ==
             %{"url" => "http://localhost:#{port}/redirect"}

    assert_received {:stub_request, "GET", "/v1/prices/price_test_monthly"}
    assert_received {:stub_request, "POST", "/v1/checkout/sessions"}

    subscription_fixture(scope)

    assert json_response(post(auth, ~p"/api/v1/settings/billing/portal-session", %{}), 201)["data"] ==
             %{"url" => "http://localhost:#{port}/redirect"}

    assert_received {:stub_request, "POST", "/v1/billing_portal/sessions"}
  end

  test "stub redirects require the exact origin and test billing mode", %{
    auth: auth,
    scope: scope,
    original: original
  } do
    subscription = subscription_fixture(scope)
    configure(original, test_api_origin: {"http", "localhost", 4200})

    for url <- [
          "http://localhost:4201/portal",
          "https://localhost:4200/portal",
          "http://127.0.0.1:4200/portal",
          "http://localhost.evil.test:4200/portal",
          "http://user@localhost:4200/portal",
          "http://checkout.stripe.com/portal",
          "https://billing.stripe.com:4200/portal"
        ] do
      Req.Test.stub(Billing.Stripe, &Req.Test.json(&1, %{url: url}))

      assert_error(
        post(auth, ~p"/api/v1/settings/billing/portal-session", %{}),
        503,
        "stripe_unavailable"
      )
    end

    StarterKit.Repo.update!(Ecto.Changeset.change(subscription, livemode: true),
      org_id: scope.organization.id
    )

    configure(original,
      mode: :live,
      secret_key: "sk_live_fake",
      test_api_origin: {"http", "localhost", 4200}
    )

    Req.Test.stub(Billing.Stripe, &Req.Test.json(&1, %{url: "http://localhost:4200/portal"}))

    assert_error(
      post(auth, ~p"/api/v1/settings/billing/portal-session", %{}),
      503,
      "stripe_unavailable"
    )
  end

  test "production config forbids a Stripe API override" do
    with_env(
      %{
        "STRIPE_API_BASE" => "http://localhost:4200/v1/",
        "SPA_ORIGIN" => "https://app.example.com",
        "CORS_ORIGINS" => "https://app.example.com"
      },
      fn ->
        assert_raise RuntimeError, "STRIPE_API_BASE cannot be overridden in production", fn ->
          Config.Reader.read!("config/runtime.exs", env: :prod)
        end
      end
    )
  end

  defp with_env(values, fun) do
    original = Map.new(values, fn {key, _} -> {key, System.get_env(key)} end)
    System.put_env(values)

    try do
      fun.()
    after
      for {key, value} <- original do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end
  end

  defp checkout,
    do: %{offerId: "pro_monthly", offerRevision: Billing.offer_revision(), accepted: true}

  defp configure(original, changes),
    do: Application.put_env(:starter_kit, Billing, Keyword.merge(original, changes))
end
