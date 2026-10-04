defmodule StarterKit.Billing do
  @moduledoc """
  Paid plans through Stripe Checkout. OFF by default (`BILLING_ENABLED`); a product
  turns it on and lists its offers in config. docs/BILLING.md has the setup.

  Rules (Toptive):

    * **Offers live on the server** (`config :starter_kit, StarterKit.Billing, offers: …`).
      The browser sends only an offer id and the offer revision it showed; a changed
      offer is refused (`:offer_changed`), never charged.
    * **The shown price is the price charged.** Before every checkout the Stripe price is
      fetched and compared with the offer (amount, currency, interval); a difference
      refuses the checkout (`:price_mismatch`). Stripe Tax (`automatic_tax`) is NEVER
      sent, and Adaptive Pricing (a converted local currency) is always off.
    * **Test checkout is never public.** In test mode (`BILLING_MODE=test`, the default)
      only superadmins and `BILLING_TEST_OPERATOR_USER_IDS` may check out. Live mode needs
      a live key (`sk_live_…`/`rk_live_…`); a key of the other mode counts as missing.
    * **Webhooks are signed.** `receive_event/2` checks the signature on the raw body and
      that the event's `livemode` matches the configured mode.
  """

  use Boundary,
    top_level?: true,
    deps: [
      StarterKit.Repo,
      StarterKit.Schema,
      StarterKit.Policy,
      StarterKit.Accounts,
      StarterKit.Organizations,
      StarterKit.Notifications,
      StarterKit.I18n,
      StarterKit.Audit,
      StarterKit.Analytics,
      StarterKit.Flags
    ],
    exports: [Subscription, SubscriptionPolicy]

  import Ecto.Query, only: [from: 2]

  require Logger

  alias StarterKit.{Analytics, Audit, Flags, I18n, Notifications, Organizations, Repo}
  alias StarterKit.Billing.{Event, EventWorker, Stripe, Subscription, Webhook}

  @checkout_hosts ["checkout.stripe.com"]
  @portal_hosts ["billing.stripe.com"]

  ## Configuration

  @doc "True when billing is turned on (the `:billing` flag, `BILLING_ENABLED=true`)."
  def enabled?, do: Flags.enabled?(:billing)

  @doc "`:test` or `:live`."
  def mode, do: if(config(:mode) == :live, do: :live, else: :test)

  @doc """
  The offers a product sells: `%{id, plan, interval, amount_cents, currency}`. The price
  id of each comes from `STRIPE_<MODE>_PRICE_<OFFER_ID>` (e.g. `STRIPE_LIVE_PRICE_PRO_MONTHLY`).
  """
  def list_offers do
    currency = config(:currency) || "usd"

    for offer <- config(:offers) || [] do
      offer |> Map.new() |> Map.put_new(:currency, currency)
    end
  end

  @doc """
  A short hash of every offer's terms. Pages send it back with the checkout, so a price
  changed between showing and paying is refused instead of charged.
  """
  def offer_revision do
    list_offers()
    |> Enum.map(&Map.take(&1, [:id, :plan, :interval, :amount_cents, :currency]))
    |> Enum.sort_by(& &1.id)
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 16)
  end

  @doc "The current tenant's billing overview, including access while sales are off."
  def overview(scope) do
    subscription = current_subscription(scope)

    if enabled?() or subscription do
      {:ok,
       %{
         plan: plan(scope),
         subscription: subscription,
         offers: list_offers(),
         offer_revision: offer_revision(),
         sales: %{status: sales(scope.user), test_mode: mode() == :test},
         can_manage: StarterKit.Policy.allowed?(scope, :manage_billing, scope.organization)
       }}
    else
      {:error, :not_found}
    end
  end

  ## Plans and limits

  @doc """
  The organization's subscription in the current mode (nil when it never subscribed).
  Rows are written by reconciliation from Stripe's answer only.
  """
  def current_subscription(%{organization: %{id: org_id}}) do
    Repo.one(from(s in Subscription, where: s.livemode == ^(mode() == :live)), org_id: org_id)
  end

  def current_subscription(_scope), do: nil

  @doc """
  Whether Stripe can still charge the organization, in either mode: `:open` (a
  subscription in any status but `canceled` or `incomplete_expired`), `:closed` (only
  ended subscriptions: billing history) or `:none`.
  """
  def subscription_state(organization_id) do
    statuses = Repo.all(from(s in Subscription, select: s.status), org_id: organization_id)

    cond do
      statuses == [] -> :none
      Enum.all?(statuses, &(&1 in ~w(canceled incomplete_expired))) -> :closed
      true -> :open
    end
  end

  @doc """
  The plan the organization has now: the subscription's plan while it is paid
  (`Subscription.paid?/2`), else the default plan (`default_plan`, `"free"`).
  """
  def plan(scope) do
    case current_subscription(scope) do
      %Subscription{} = sub -> if Subscription.paid?(sub), do: sub.plan, else: default_plan()
      nil -> default_plan()
    end
  end

  @doc """
  The limit `key` of the organization's plan: an integer, or `:unlimited` (`nil` in
  config). With billing OFF every limit is `:unlimited`. A key missing from the plan
  raises: every plan in `config :starter_kit, StarterKit.Billing, plans:` lists every key.
  """
  def limit(scope, key) when is_atom(key) do
    if enabled?() do
      plan = plan(scope)
      limits = Map.get(config(:plans) || %{}, plan) || raise ArgumentError, "unknown plan #{plan}"

      case Map.fetch(limits, key) do
        {:ok, nil} -> :unlimited
        {:ok, max} when is_integer(max) -> max
        :error -> raise ArgumentError, "plan #{plan} has no limit #{inspect(key)}"
      end
    else
      :unlimited
    end
  end

  @doc """
  Runs `write_fun` only while the organization is under its `key` limit, counting and
  writing in ONE transaction that locks the organization row, so two parallel requests
  cannot both take the last place.

      Billing.with_capacity(scope, :members,
        fn -> Repo.aggregate(Membership, :count, org_id: org_id) end,
        fn -> Repo.insert(changeset) end)

  `write_fun` returns `{:ok, value}` or `{:error, reason}`. Over the limit:
  `{:error, {:limit_reached, key, limit}}`, and `write_fun` is not called.
  """
  def with_capacity(%{organization: %{id: org_id}} = scope, key, count_fun, write_fun)
      when is_function(count_fun, 0) and is_function(write_fun, 0) do
    Repo.transact(fn ->
      lock_organization(org_id) || raise(Ecto.NoResultsError, queryable: "organizations")

      scope |> limit(key) |> write_within(key, count_fun, write_fun)
    end)
  end

  @doc "Reserves invitation capacity and creates the invitation under the organization lock."
  def invite_member(scope, attrs, url_fun, locale) do
    if Notifications.email_available?() do
      with_capacity(scope, :members, fn -> Organizations.invitation_seat_count(scope) end, fn ->
        Organizations.create_invitation(scope, attrs, url_fun, locale)
      end)
    else
      {:error, :email_unavailable}
    end
  end

  defp write_within(:unlimited, _key, _count_fun, write_fun), do: write_fun.()

  defp write_within(max, key, count_fun, write_fun) do
    if count_fun.() < max, do: write_fun.(), else: {:error, {:limit_reached, key, max}}
  end

  defp default_plan, do: config(:default_plan) || "free"

  ## Customer portal

  @doc """
  Opens Stripe's customer portal (change card, see invoices, cancel) for the
  organization's subscription and returns its URL. It does NOT depend on
  `BILLING_ENABLED`: a customer can always cancel, even when sales are off; it needs
  only the key of the current mode and a subscription.

  Errors: `:not_configured`, `:no_subscription`, `{:stripe, status, details}`,
  `:stripe_unreachable`.
  """
  def create_portal_session(%{user: user} = scope, return_url) do
    with {:ok, secret_key} <- secret_key(),
         %Subscription{} = sub <- current_subscription(scope) || {:error, :no_subscription},
         {:ok, %{"url" => url}} <-
           Stripe.post(
             "billing_portal/sessions",
             [
               {"customer", sub.stripe_customer_id},
               {"return_url", return_url},
               {"locale", user.locale || "auto"}
             ],
             secret_key,
             nil
           ),
         :ok <- stripe_url(url, @portal_hosts) do
      Audit.record("billing.portal_opened", scope: scope, subject: sub)
      {:ok, url}
    end
  end

  ## Renewal notices

  @doc """
  Sends one renewal notice per period to the people who manage billing (owners and
  admins with full access) of every subscription that renews in the notice window
  (`renewal_notice_days`, default 25 to 15 days before) and has an interval in
  `renewal_notice_intervals` (default `["year"]`). Runs daily (`NoticeSweepWorker`).

  The amount is Stripe's own preview of the next invoice (discounts included), so the
  email says exactly what will be charged. Not sent for a subscription that will not renew
  (canceled at period end, paused, not active). OFF unless `BILLING_RENEWAL_NOTICES=true`;
  it does not depend on `BILLING_ENABLED` (customers who already pay still renew).
  A failed preview is retried the next day while the window lasts.
  """
  def send_renewal_notices(now \\ DateTime.utc_now(:second)) do
    with true <- Flags.enabled?(:billing_renewal_notices),
         {:ok, key} <- secret_key() do
      now |> renewal_notices_due() |> Enum.each(&send_renewal_notice(&1, key))
    end

    :ok
  end

  defp renewal_notices_due(now) do
    intervals = config(:renewal_notice_intervals) || ["year"]
    offers = Map.new(list_offers(), &{&1.id, &1})

    now
    |> due_query(config(:renewal_notice_days) || [from: 25, until: 15])
    |> Repo.all(skip_org_id: true)
    |> Enum.filter(fn sub ->
      offer = offers[sub.offer_id]
      offer != nil and offer.interval in intervals
    end)
  end

  # Renewing subscriptions of this mode whose period ends inside the window and whose
  # notice for that period is not sent yet.
  defp due_query(now, days) do
    from(s in Subscription,
      where:
        s.livemode == ^(mode() == :live) and s.status in ["active", "trialing"] and
          not s.cancel_at_period_end and not s.paused and
          s.current_period_end >= ^DateTime.add(now, days[:until], :day) and
          s.current_period_end <= ^DateTime.add(now, days[:from], :day) and
          (is_nil(s.renewal_notice_sent_for) or
             s.renewal_notice_sent_for != s.current_period_end)
    )
  end

  defp send_renewal_notice(%Subscription{} = sub, key) do
    case Stripe.post(
           "invoices/create_preview",
           [{"subscription", sub.stripe_subscription_id}],
           key,
           nil
         ) do
      {:ok, %{"amount_due" => cents, "currency" => currency}} when is_integer(cents) ->
        Repo.transact(fn -> claim_and_notify(sub, cents, currency) end)

      _error ->
        Logger.warning(
          "billing: no invoice preview for #{sub.stripe_subscription_id}; retry tomorrow"
        )
    end
  end

  # The conditional update claims the period: a second sweep (or a parallel one) finds
  # nothing to claim. The emails are queued in the same transaction.
  defp claim_and_notify(sub, cents, currency) do
    claim =
      from(s in Subscription,
        where:
          s.id == ^sub.id and
            (is_nil(s.renewal_notice_sent_for) or
               s.renewal_notice_sent_for != ^sub.current_period_end)
      )

    case Repo.update_all(claim, [set: [renewal_notice_sent_for: sub.current_period_end]],
           org_id: sub.organization_id
         ) do
      {1, _} ->
        for user <- billing_managers(sub.organization_id) do
          {:ok, _job} =
            Notifications.notify(user, :renewal_notice, notice_data(sub, user, cents, currency))
        end

        Audit.record("billing.renewal_notice_queued",
          organization_id: sub.organization_id,
          subject: sub,
          metadata: %{amount_cents: cents, currency: currency}
        )

        {:ok, :sent}

      {0, _} ->
        {:ok, :already_sent}
    end
  end

  defp billing_managers(org_id) do
    %StarterKit.Organizations.Organization{id: org_id}
    |> Organizations.list_organization_memberships()
    |> Enum.filter(&(&1.role in [:owner, :admin] and &1.access == :full))
    |> Enum.map(& &1.user)
  end

  defp notice_data(sub, user, cents, currency) do
    %{
      plan: I18n.t("billing.plan.#{sub.plan}", %{}, user.locale),
      date: sub.current_period_end |> DateTime.to_date() |> Date.to_iso8601(),
      amount: format_amount(cents, currency),
      url: config(:manage_url),
      # A Stripe test-mode subscription: the email carries a "Test mode" badge.
      test: not sub.livemode
    }
  end

  # "USD 190.00". Two decimals: Stripe's zero-decimal currencies (JPY, KRW…) need a
  # product change here.
  @doc false
  def format_amount(cents, currency) do
    fraction = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{String.upcase(currency)} #{div(cents, 100)}.#{fraction}"
  end

  ## Boot check

  @doc """
  What stops billing from working: a missing key or a key of the other mode, a missing
  webhook secret, an offer without its price id, an offer of an unknown plan, plans with
  different limit keys. Billing ON with a problem stops the boot in production
  (`StarterKit.Flags.check!/1`). A test-mode deployment stays possible (operators only),
  never a public test checkout.
  """
  def config_problems do
    plans = config(:plans) || %{}
    prefix = mode() |> to_string() |> String.upcase()

    limit_keys =
      plans |> Map.values() |> Enum.map(&(&1 |> Map.keys() |> Enum.sort())) |> Enum.uniq()

    [
      {not key_for_mode?(config(:secret_key)),
       "STRIPE_#{prefix}_SECRET_KEY is missing or of the other mode"},
      {webhook_secret() == {:error, :not_configured}, "STRIPE_#{prefix}_WEBHOOK_SECRET is missing"},
      {length(limit_keys) > 1, "every plan must list the same limit keys"},
      {not Map.has_key?(plans, default_plan()), "default_plan #{default_plan()} is not in plans"}
    ]
    |> Enum.concat(
      for offer <- list_offers() do
        [
          {price_id(offer) == {:error, :not_configured},
           "STRIPE_#{prefix}_PRICE_#{String.upcase(offer.id)} is missing"},
          {not Map.has_key?(plans, offer.plan),
           "offer #{offer.id}: plan #{offer.plan} is not in plans"}
        ]
      end
      |> List.flatten()
    )
    |> Enum.flat_map(fn {problem?, message} -> if problem?, do: [message], else: [] end)
  end

  ## Checkout

  @doc """
  Starts a Stripe Checkout session for the scope's organization and returns its URL.

  `params`: `"offer_id"`, `"offer_revision"` (from `offer_revision/0`, as shown) and
  `"accepted"` (the customer ticked the terms). `urls`: `%{success_url, cancel_url}`.

  Errors: `:disabled`, `:not_configured`, `:test_mode` (not an operator),
  `:already_subscribed` (a paid plan is changed in the portal, never bought twice),
  `:unknown_offer`, `:offer_changed`, `:not_accepted`, `:price_mismatch`,
  `{:stripe, status, details}`, `:stripe_unreachable`.
  """
  def create_checkout_session(%{user: user, organization: org} = scope, params, urls)
      when not is_nil(user) and not is_nil(org) do
    with {:ok, secret_key} <- available_for(user),
         :ok <- not_subscribed(scope),
         {:ok, offer} <- fetch_offer(params["offer_id"]),
         :ok <- same_revision(params["offer_revision"]),
         :ok <- accepted(params["accepted"]),
         {:ok, price_id} <- price_id(offer),
         :ok <- same_price(offer, price_id, secret_key),
         {:ok, %{"url" => url}} <-
           Stripe.post(
             "checkout/sessions",
             checkout_form(offer, price_id, user, org, urls),
             secret_key,
             idempotency_key(user, org, offer)
           ),
         :ok <- stripe_url(url, @checkout_hosts) do
      Audit.record("billing.checkout_started",
        scope: scope,
        subject: org,
        metadata: %{offer_id: offer.id, offer_revision: offer_revision(), mode: mode()}
      )

      Analytics.track("checkout_started", scope, %{
        plan: offer.plan,
        interval: offer.interval,
        mode: mode()
      })

      {:ok, url}
    end
  end

  @doc """
  Whether `user` may start a checkout now: `:open` (live), `:test` (test mode, an
  operator: Stripe test cards only) or `:closed` (billing off, no key, or test mode for
  everyone else). Pages use it to show or hide the pay button.
  """
  def sales(user) do
    case available_for(user) do
      {:ok, _key} -> if mode() == :test, do: :test, else: :open
      {:error, _reason} -> :closed
    end
  end

  defp available_for(user) do
    cond do
      not enabled?() -> {:error, :disabled}
      not key_for_mode?(config(:secret_key)) -> {:error, :not_configured}
      mode() == :test and not operator?(user) -> {:error, :test_mode}
      true -> {:ok, config(:secret_key)}
    end
  end

  defp secret_key do
    key = config(:secret_key)
    if key_for_mode?(key), do: {:ok, key}, else: {:error, :not_configured}
  end

  defp key_for_mode?(key) when is_binary(key) do
    prefix = if mode() == :live, do: "_live_", else: "_test_"
    String.starts_with?(key, ["sk" <> prefix, "rk" <> prefix])
  end

  defp key_for_mode?(_key), do: false

  defp operator?(user),
    do: user.role == :superadmin or user.id in (config(:test_operator_user_ids) || [])

  defp not_subscribed(scope) do
    case current_subscription(scope) do
      %Subscription{} = sub ->
        if Subscription.paid?(sub), do: {:error, :already_subscribed}, else: :ok

      nil ->
        :ok
    end
  end

  defp fetch_offer(id) do
    case Enum.find(list_offers(), &(&1.id == id)) do
      nil -> {:error, :unknown_offer}
      offer -> {:ok, offer}
    end
  end

  defp same_revision(revision) do
    if is_binary(revision) and Plug.Crypto.secure_compare(revision, offer_revision()),
      do: :ok,
      else: {:error, :offer_changed}
  end

  defp accepted(value) when value in [true, "true"], do: :ok
  defp accepted(_value), do: {:error, :not_accepted}

  defp price_id(offer) do
    case (config(:prices) || %{})[String.upcase(offer.id)] do
      "price_" <> _ = id -> {:ok, id}
      _ -> {:error, :not_configured}
    end
  end

  # "The shown price is the price charged": Stripe's price must be exactly the offer.
  defp same_price(offer, price_id, secret_key) do
    with {:ok, price} <- Stripe.get("prices/#{URI.encode(price_id)}", secret_key) do
      if price["active"] == true and price["livemode"] == (mode() == :live) and
           price["unit_amount"] == offer.amount_cents and
           price["currency"] == String.downcase(offer.currency) and
           get_in(price, ["recurring", "interval"]) == to_string(offer.interval) do
        :ok
      else
        Logger.error("billing: Stripe price for offer #{offer.id} does not match the offer")
        {:error, :price_mismatch}
      end
    end
  end

  defp checkout_form(offer, price_id, user, org, urls) do
    [
      {"mode", "subscription"},
      {"line_items[0][price]", price_id},
      {"line_items[0][quantity]", "1"},
      {"success_url", urls.success_url},
      {"cancel_url", urls.cancel_url},
      {"client_reference_id", org.id},
      {"customer_email", user.email},
      {"locale", user.locale || "auto"},
      {"allow_promotion_codes", "true"},
      # A 100 % promotion code needs no card.
      {"payment_method_collection", "if_required"},
      # The charged amount is the offer, in the offer's currency: no converted local
      # price, and never Stripe Tax (`automatic_tax` is not sent at all).
      {"adaptive_pricing[enabled]", "false"},
      # Said again on Stripe's page, above the pay button, in the customer's language.
      {"custom_text[submit][message]", I18n.t("billing.price_note", %{}, user.locale)},
      {"metadata[organization_id]", org.id},
      {"metadata[offer_id]", offer.id},
      {"metadata[offer_revision]", offer_revision()},
      {"subscription_data[metadata][organization_id]", org.id},
      {"subscription_data[metadata][offer_id]", offer.id}
    ]
  end

  # Repeated clicks within the hour reuse the same session instead of opening new ones.
  defp idempotency_key(user, org, offer) do
    hour = div(System.system_time(:second), 3600)
    "checkout-v1-#{org.id}-#{user.id}-#{offer.id}-#{offer_revision()}-#{hour}"
  end

  # Never send a customer to a page Stripe did not host.
  defp stripe_url(url, hosts) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} -> if host in hosts, do: :ok, else: unexpected()
      _ -> unexpected()
    end
  end

  defp unexpected, do: {:error, :unexpected_stripe_url}

  ## Webhooks and reconciliation

  # The events that can change a subscription. Others are verified and acknowledged.
  @handled_events ~w(checkout.session.completed customer.subscription.created
    customer.subscription.updated customer.subscription.deleted customer.subscription.paused
    customer.subscription.resumed invoice.paid invoice.payment_failed)

  @doc """
  Verifies a Stripe webhook (`raw_body` exactly as received, the `Stripe-Signature`
  header) and puts a subscription event in the inbox (`billing_events`, ids only) with a
  job that reconciles it. A repeated delivery is a no-op. Returns `{:ok, event_type}`.

  It needs only the webhook secret of the current mode, not `BILLING_ENABLED`: turning
  sales off never stops cancellations and renewals from being recorded. Without a
  secret: `{:error, :not_configured}` (the endpoint answers 404).
  """
  def receive_event(raw_body, signature) do
    with {:ok, secret} <- webhook_secret(),
         :ok <- Webhook.verify(raw_body, signature, secret),
         {:ok, %{"id" => "evt_" <> _, "type" => type, "livemode" => livemode} = event} <-
           Jason.decode(raw_body),
         true <- livemode == (mode() == :live) || {:error, :wrong_mode} do
      if type in @handled_events, do: enqueue_event(event), else: {:ok, type}
    else
      {:ok, _other} -> {:error, :invalid_event}
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_event}
      {:error, _reason} = error -> error
    end
  end

  defp webhook_secret do
    case config(:webhook_secret) do
      "whsec_" <> _ = secret -> {:ok, secret}
      _ -> {:error, :not_configured}
    end
  end

  defp enqueue_event(%{"id" => event_id, "type" => type, "livemode" => livemode} = event) do
    {subscription_id, organization_hint} = subscription_ref(event)

    row = %Event{
      livemode: livemode,
      stripe_event_id: event_id,
      type: type,
      stripe_subscription_id: subscription_id,
      organization_id: uuid(organization_hint)
    }

    Repo.transact(fn ->
      with {:ok, row} <- row |> Ecto.Changeset.change() |> event_unique() |> Repo.insert(),
           {:ok, _job} <- Oban.insert(EventWorker.new(%{event_id: row.id})) do
        {:ok, type}
      end
    end)
    |> case do
      {:error, %Ecto.Changeset{errors: [stripe_event_id: _]}} -> {:ok, type}
      result -> result
    end
  end

  defp event_unique(changeset),
    do:
      Ecto.Changeset.unique_constraint(changeset, :stripe_event_id,
        name: :billing_events_livemode_stripe_event_id_index
      )

  # Which subscription an event is about, and the organization it claims (a hint only).
  defp subscription_ref(%{"type" => "checkout.session.completed", "data" => %{"object" => obj}}),
    do:
      {sub_id(obj["subscription"]),
       get_in(obj, ["metadata", "organization_id"]) || obj["client_reference_id"]}

  defp subscription_ref(%{"type" => "customer.subscription." <> _, "data" => %{"object" => obj}}),
    do: {sub_id(obj["id"]), get_in(obj, ["metadata", "organization_id"])}

  # API 2025-03-31 and later: invoice.parent.subscription_details; older: invoice.subscription.
  defp subscription_ref(%{"type" => "invoice." <> _, "data" => %{"object" => obj}}) do
    details = get_in(obj, ["parent", "subscription_details"]) || %{}

    {sub_id(details["subscription"] || obj["subscription"]),
     get_in(details, ["metadata", "organization_id"])}
  end

  defp subscription_ref(_event), do: {nil, nil}

  defp sub_id("sub_" <> _ = id), do: id
  defp sub_id(_), do: nil

  defp uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  @doc """
  Reconciles one inbox event (called by `Billing.EventWorker`): fetches the subscription
  from Stripe (the webhook payload is never trusted on its own, and event order does not
  matter) and upserts the organization's row under a lock on the organization.
  Processing an event twice is harmless. Stripe errors return `{:error, _}` (Oban retries).
  """
  def process_event(event_id) do
    case Repo.get(Event, event_id) do
      %Event{processed_at: nil} = event -> reconcile(event)
      _done_or_missing -> :ok
    end
  end

  defp reconcile(%Event{stripe_subscription_id: nil} = event), do: finish(event, "no_subscription")

  defp reconcile(%Event{} = event) do
    with {:ok, key} <- secret_key(),
         {:ok, stripe_sub} <-
           Stripe.get("subscriptions/#{URI.encode(event.stripe_subscription_id)}", key) do
      finish(event, sync_subscription(stripe_sub, event.organization_id))
    end
  end

  defp finish(event, outcome) do
    event
    |> Ecto.Changeset.change(processed_at: DateTime.utc_now(:second), outcome: outcome)
    |> Repo.update!()

    Logger.info("billing: #{event.type} #{event.stripe_event_id} → #{outcome}")
    :ok
  end

  defp sync_subscription(%{"livemode" => livemode} = stripe_sub, organization_hint) do
    org_id = uuid(get_in(stripe_sub, ["metadata", "organization_id"])) || organization_hint
    attrs = subscription_attrs(stripe_sub)

    cond do
      livemode != (mode() == :live) -> "wrong_mode"
      is_nil(org_id) -> "unknown_organization"
      true -> upsert_subscription(org_id, attrs)
    end
  end

  defp upsert_subscription(org_id, attrs) do
    {:ok, {outcome, funnel_event}} =
      Repo.transact(fn ->
        if lock_organization(org_id) do
          existing =
            Repo.one(from(s in Subscription, where: s.livemode == ^attrs.livemode), org_id: org_id)

          {:ok, write_subscription(existing, org_id, attrs)}
        else
          {:ok, {"unknown_organization", nil}}
        end
      end)

    # After the commit: a webhook has no user, so the event is anonymous (a count).
    if funnel_event, do: Analytics.track(funnel_event, nil, funnel_props(attrs))
    outcome
  end

  # The organization starts or stops paying: the end of the revenue funnel.
  defp funnel_event(existing, attrs) do
    was_paid = existing != nil and Subscription.paid?(existing)
    paid = Subscription.paid?(struct(Subscription, attrs))

    cond do
      paid and not was_paid -> "subscription_started"
      was_paid and not paid -> "subscription_canceled"
      true -> nil
    end
  end

  defp funnel_props(attrs) do
    offer = Enum.find(list_offers(), &(&1.id == attrs.offer_id))
    %{plan: attrs.plan, interval: offer && offer.interval, mode: mode()}
  end

  # An older subscription's event must not replace a newer paid one (a customer who
  # subscribed again, events out of order): a paid row is kept against an unpaid other one.
  defp write_subscription(%Subscription{} = existing, org_id, attrs) do
    incoming = struct(Subscription, attrs)

    if existing.stripe_subscription_id != attrs.stripe_subscription_id and
         Subscription.paid?(existing) and not Subscription.paid?(incoming) do
      {"kept_paid_subscription", nil}
    else
      existing |> Ecto.Changeset.change(attrs) |> Repo.update!()

      if existing.plan != attrs.plan or existing.status != attrs.status,
        do: audit_sync(org_id, attrs)

      {"synced", funnel_event(existing, attrs)}
    end
  end

  defp write_subscription(nil, org_id, attrs) do
    Repo.insert!(struct(Subscription, Map.put(attrs, :organization_id, org_id)))
    audit_sync(org_id, attrs)
    {"synced", funnel_event(nil, attrs)}
  end

  defp audit_sync(org_id, attrs) do
    Audit.record("billing.subscription_changed",
      organization_id: org_id,
      metadata: Map.take(attrs, [:plan, :status, :offer_id, :stripe_subscription_id])
    )
  end

  # Only what entitlements need, read from Stripe's own subscription object. In API
  # 2025-03-31 and later the period end lives on the subscription item.
  defp subscription_attrs(stripe_sub) do
    item = get_in(stripe_sub, ["items", "data", Access.at(0)]) || %{}
    offer = offer_for(get_in(item, ["price", "id"]), get_in(stripe_sub, ["metadata", "offer_id"]))
    period_end = item["current_period_end"] || stripe_sub["current_period_end"]

    %{
      livemode: stripe_sub["livemode"],
      stripe_customer_id: id_of(stripe_sub["customer"]),
      stripe_subscription_id: stripe_sub["id"],
      offer_id: offer && offer.id,
      plan: (offer && offer.plan) || default_plan(),
      status: stripe_sub["status"],
      current_period_end: period_end && DateTime.from_unix!(period_end),
      cancel_at_period_end: stripe_sub["cancel_at_period_end"] == true,
      paused: not is_nil(stripe_sub["pause_collection"])
    }
  end

  # The price id decides the offer (Stripe's truth); the checkout metadata is a fallback.
  # An unknown price gives the default plan and an error log, never a paid plan by guess.
  defp offer_for(price_id, metadata_offer_id) do
    offer_id = if price_id, do: price_offer_id(price_id), else: metadata_offer_id
    offer = Enum.find(list_offers(), &(&1.id == offer_id))

    if is_nil(offer),
      do: Logger.error("billing: Stripe price #{inspect(price_id)} matches no offer")

    offer
  end

  defp price_offer_id(price_id) do
    Enum.find_value(config(:prices) || %{}, fn {offer_key, id} ->
      if id == price_id, do: String.downcase(offer_key)
    end)
  end

  defp id_of(%{"id" => id}), do: id
  defp id_of(id), do: id

  defp lock_organization(org_id) do
    Repo.one(
      from(o in "organizations",
        where: o.id == type(^org_id, Ecto.UUID),
        select: o.id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp config(key), do: Application.get_env(:starter_kit, __MODULE__, []) |> Keyword.get(key)
end
