defmodule StarterKit.BillingNoticesTest do
  # Changes the global billing config: not async.
  use StarterKit.DataCase, async: false

  import Swoosh.TestAssertions

  alias StarterKit.Audit.AuditEvent
  alias StarterKit.Billing

  setup do
    original = Application.get_env(:starter_kit, Billing)
    on_exit(fn -> Application.put_env(:starter_kit, Billing, original) end)

    put_flag(:billing_renewal_notices, true)

    Application.put_env(
      :starter_kit,
      Billing,
      Keyword.merge(original, manage_url: "https://app.example.com/dashboard")
    )

    %{original: original}
  end

  defp renews_in(days), do: DateTime.utc_now(:second) |> DateTime.add(days, :day)

  defp yearly(scope, attrs \\ []),
    do:
      subscription_fixture(
        scope,
        Keyword.merge([offer_id: "pro_yearly", current_period_end: renews_in(20)], attrs)
      )

  defp stub_preview(amount \\ 19_000) do
    test = self()

    Req.Test.stub(Billing.Stripe, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:preview, conn.request_path, URI.decode_query(body)})
      Req.Test.json(conn, %{"amount_due" => amount, "currency" => "usd"})
    end)
  end

  test "a yearly renewal in the window: one email with Stripe's exact amount, once" do
    scope = scope_fixture()
    sub = yearly(scope)
    stub_preview()

    assert :ok = Billing.send_renewal_notices()

    assert_received {:preview, "/v1/invoices/create_preview", %{"subscription" => sub_id}}
    assert sub_id == sub.stripe_subscription_id

    date = sub.current_period_end |> DateTime.to_date() |> Date.to_iso8601()

    assert_email_sent(fn email ->
      assert email.to == [{scope.user.name, scope.user.email}]
      assert email.subject =~ date
      assert email.text_body =~ "USD 190.00"
      assert email.text_body =~ "nothing is added"
      assert email.text_body =~ "https://app.example.com/dashboard"
    end)

    assert Repo.get_by(AuditEvent, action: "billing.renewal_notice_queued")

    # The next day's sweep: already sent for this period, Stripe is not even asked.
    assert :ok = Billing.send_renewal_notices()
    refute_received {:preview, _, _}
    refute_email_sent()
  end

  test "only the people who manage billing get it" do
    scope = scope_fixture()
    admin = user_fixture()
    member = user_fixture()
    membership_fixture(scope, admin, :admin)
    membership_fixture(scope, member, :member)
    yearly(scope)
    stub_preview()

    Billing.send_renewal_notices()

    recipients =
      for _ <- 1..2 do
        assert_received {:email, %{to: [{_, to}]}}
        to
      end

    assert Enum.sort(recipients) == Enum.sort([scope.user.email, admin.email])
    refute_received {:email, _}
  end

  test "no notice: monthly plans, outside the window, canceled at period end, paused" do
    stub_preview()

    for attrs <- [
          [offer_id: "pro_monthly"],
          [current_period_end: renews_in(40)],
          [current_period_end: renews_in(5)],
          [cancel_at_period_end: true],
          [paused: true],
          [status: "past_due"]
        ] do
      yearly(scope_fixture(), attrs)
    end

    Billing.send_renewal_notices()
    refute_received {:preview, _, _}
    refute_email_sent()
  end

  test "OFF: nothing is sent" do
    put_flag(:billing_renewal_notices, false)
    yearly(scope_fixture())
    Req.Test.stub(Billing.Stripe, fn _conn -> flunk("Stripe must not be called") end)

    assert :ok = Billing.send_renewal_notices()
    refute_email_sent()
  end

  test "a failed preview claims nothing: the next sweep sends it" do
    scope = scope_fixture()
    yearly(scope)
    Req.Test.stub(Billing.Stripe, &(&1 |> Plug.Conn.put_status(500) |> Req.Test.json(%{})))

    ExUnit.CaptureLog.capture_log(fn -> Billing.send_renewal_notices() end)
    refute_email_sent()

    stub_preview()
    Billing.send_renewal_notices()
    assert_email_sent(to: [{scope.user.name, scope.user.email}])
  end

  describe "boot check" do
    test "the test setup is complete" do
      assert Billing.config_problems() == []
    end

    test "names every missing piece; billing ON with a problem stops the boot",
         %{original: original} do
      Application.put_env(
        :starter_kit,
        Billing,
        Keyword.merge(original,
          secret_key: "sk_live_wrong_mode",
          webhook_secret: nil,
          prices: %{"PRO_MONTHLY" => "price_1"}
        )
      )

      problems = Billing.config_problems()
      assert "STRIPE_TEST_SECRET_KEY is missing or of the other mode" in problems
      assert "STRIPE_TEST_WEBHOOK_SECRET is missing" in problems
      assert "STRIPE_TEST_PRICE_PRO_YEARLY is missing" in problems

      assert_raise RuntimeError,
                   ~r/flags are ON but not ready:\n  BILLING_ENABLED: STRIPE_TEST_SECRET_KEY/,
                   fn -> StarterKit.Flags.check!(billing: &Billing.config_problems/0) end
    end

    test "billing OFF never stops the boot", %{original: original} do
      put_flag(:billing, false)
      Application.put_env(:starter_kit, Billing, Keyword.merge(original, secret_key: nil))

      assert :ok = StarterKit.Flags.check!(billing: &Billing.config_problems/0)
    end
  end

  test "amounts are shown with the currency and two decimals" do
    assert Billing.format_amount(19_000, "usd") == "USD 190.00"
    assert Billing.format_amount(5, "eur") == "EUR 0.05"
  end
end
