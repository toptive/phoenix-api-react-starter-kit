# Billing (Stripe)

`StarterKit.Billing` sells subscriptions through Stripe Checkout. It is **OFF** in every
new product; turn it on only when the product sells something.

What exists today: server-owned offers, the Checkout session, signed webhooks with
reconciliation, plans and limits (`plan/1`, `limit/2`, `with_capacity/4`) read from the
stored subscription, the customer portal, renewal notices, a boot check, the billing page
(`/settings/billing`) and the deploy switch with its guard (`config/deploy.yml`).

## Rules

1. **Offers live on the server.** `config :starter_kit, StarterKit.Billing, offers: […]`
   holds every offer: `id`, `plan`, `interval` (`"month"`/`"year"`), `amount_cents`,
   optional `currency` (default `currency`, `"usd"`). The browser sends only the offer id and
   the offer revision (`Billing.offer_revision/0`) that it showed. A changed offer is refused
   (`:offer_changed`); it is never charged.
2. **The shown price is the price charged.** Before every checkout, the Stripe price is
   fetched and compared with the offer (amount, currency, interval, active, mode). Any
   difference refuses the checkout (`:price_mismatch`, logged as an error). Copy key:
   `billing.price_note` ("The price you see is the price you pay. Nothing is added at checkout."),
   also shown on Stripe's page above the pay button (`custom_text[submit][message]`, in the
   customer's language). Renewal notices say the exact amount from Stripe's invoice preview.
3. **Never Stripe Tax.** `automatic_tax` is never sent (a test fails if any `tax` parameter
   appears). Never write "plus tax" or "taxes may apply" in copy: a test fails when any text in
   `i18n/translations.csv` mentions tax (tax, VAT, GST, impuesto, IVA).
4. **Never a converted currency.** `adaptive_pricing[enabled]=false` on every session: the
   customer pays the offer's currency and amount (a USD 19 offer once charged HKD 155.06).
5. **Test checkout is never public.** One mode per deployment (`BILLING_MODE`). In `test` mode
   (the default) only superadmins and `BILLING_TEST_OPERATOR_USER_IDS` may check out. `live`
   mode needs a live key; a key of the other mode counts as missing. In production, billing ON
   with an incomplete setup stops the boot (`StarterKit.Flags.check!/1`, `check_on_boot: true`
   in `config/prod.exs`): a key
   missing or of the other mode, no webhook secret, an offer without its price id, an offer of
   an unknown plan, plans with different limit keys. The error lists every problem.
6. **Webhooks are signed.** Raw bytes (`Plugs.RawBody`), HMAC-SHA256 with the endpoint
   secret, constant-time compare, 5-minute tolerance, and the event's `livemode` must match
   the mode. The payload is never trusted on its own: reconciliation fetches the
   subscription from Stripe.
7. **Customers can always cancel.** The portal and the webhook do not depend on
   `BILLING_ENABLED`; they need only the key (portal) or webhook secret (webhook) of the
   current mode, so a cancellation is recorded even when sales are off. To stop selling, remove
   the offers; do not turn `BILLING_ENABLED` off while customers pay (that also turns off
   every limit and plan check).
8. Only owners and admins with full access buy for an organization (`:manage_billing`).
   Stripe error messages are never logged (they can hold customer data); only `type`,
   `code` and `param` are logged.

## Plans and limits

```elixir
config :starter_kit, StarterKit.Billing,
  default_plan: "free",
  plans: %{"free" => %{members: 3}, "pro" => %{members: nil}}   # nil = unlimited
```

- `Billing.plan(scope)`: the plan of the organization's subscription while it is paid,
  else `default_plan`. Paid = status `active`, `trialing` or `past_due` (Stripe is still
  retrying the card; its dunning settings decide when it cancels), collection not paused,
  and `current_period_end` in the future. A subscription of the other mode never counts.
- `Billing.limit(scope, :members)`: an integer or `:unlimited`. Every plan lists every key;
  a missing key raises. With billing OFF every limit is `:unlimited`.
- `Billing.with_capacity(scope, key, count_fun, write_fun)`: count and write in one
  transaction that locks the organization row, so two parallel requests cannot both take
  the last place. Over the limit: `{:error, {:limit_reached, key, limit}}`. Call it from the
  context that creates the limited thing:

```elixir
Billing.with_capacity(scope, :members,
  fn -> Repo.aggregate(Membership, :count, org_id: scope.organization.id) end,
  fn -> Repo.insert(changeset) end)
```

The subscription row (`billing_subscriptions`, one per organization and mode, a tenant
table) is written only from Stripe's answer, never from a browser.

## Reconciliation

```
POST /webhooks/stripe/events
  → Billing.receive_event/2: signature, livemode, event type
  → billing_events row (ids only: event, type, subscription, organization hint) + Oban job,
    in one transaction; a repeated delivery hits the unique (livemode, stripe_event_id): no-op
  → Billing.EventWorker → Billing.process_event/1
  → GET /v1/subscriptions/:id (Stripe's answer; the payload is never trusted)
  → lock the organization row → upsert billing_subscriptions → audit when plan/status change
  → billing_events.outcome: synced | kept_paid_subscription | unknown_organization |
    no_subscription | wrong_mode
```

- Handled events: `checkout.session.completed`, `customer.subscription.created|updated|
  deleted|paused|resumed`, `invoice.paid`, `invoice.payment_failed`. Others get a 200 and
  are not stored.
- The organization comes from the subscription's `metadata.organization_id` (set at
  checkout), else the event's hint; it must exist. The offer and plan come from the price id
  (`STRIPE_<MODE>_PRICE_*`); an unknown price gives the default plan and an error log.
- Event order does not matter: every job reads the current state from Stripe. One rule
  guards against an old subscription's late event: a stored paid subscription is never
  replaced by a different, unpaid one (`kept_paid_subscription`).
- A Stripe failure returns an error; Oban retries (10 attempts) and the event stays
  unprocessed until then. `Billing.process_event/1` can be run again by hand.

## Renewal notices

`BILLING_RENEWAL_NOTICES=true` turns them on (off by default). `Billing.NoticeSweepWorker`
runs daily at 08:00 UTC (Oban Cron) and calls `Billing.send_renewal_notices/0`:

- Which subscriptions: this mode, status `active` or `trialing`, not canceled at period
  end, not paused, an offer interval in `renewal_notice_intervals` (default `["year"]`), and
  a renewal between `renewal_notice_days[:from]` and `[:until]` days away (default 25 to 15).
- The amount: `POST /v1/invoices/create_preview` for the subscription, so discounts are
  included and the email says exactly what will be charged ("USD 190.00"; two decimals —
  zero-decimal currencies need a product change in `format_amount/2`).
- Who: the organization's owners and admins with full access, in their own language
  (`mail.renewal_notice.*`). The button goes to `manage_url`
  (`https://<PHX_HOST>/settings/billing`).
- Once per period: a conditional update claims the period (`renewal_notice_sent_for`) and
  queues the emails in the same transaction; the next sweep skips it without calling
  Stripe. A failed preview claims nothing and is retried the next day while the window lasts.
- It does not depend on `BILLING_ENABLED`: customers who already pay still renew.

## Billing page

`GET /settings/billing` (`Settings.BillingController`, `pages/settings/billing/show.tsx`), in
the settings menu under the organization while `BILLING_ENABLED=true` (the `:billing` flag,
shared prop `flags.billing`). With billing OFF it answers 404, unless the organization has a subscription:
then the page stays reachable (the renewal email links to it) so the customer can cancel.

- **Current plan**: the plan name and one sentence about what happens next: renews on a
  date, ends on a date, payment failed (update the card), paused, or ended.
- **Manage payments**: the portal button, shown to owners and admins whenever a
  subscription exists (paid or not).
- **Offer cards** (radio cards, never a `<select>`), only while the organization has no paid
  plan. Each card: plan, interval, the exact price (`formatMoney`) and
  `billing.plan_summary.<plan>`. Under the cards: ONE accept box (`billing.accept`: terms,
  privacy, "I agree to pay {{price}} {{period}} until I cancel"), the pay button with the
  price, and `billing.price_note`. The form posts the offer id, the offer revision of the
  page and the box; the server checks all three again.
- **Who can pay** (`Billing.sales/1`): `:open` in live mode; `:test` for operators in test
  mode (a "Test mode" banner); `:closed` for everyone else ("Paid plans are not available
  yet"). Members see the plan and the prices but not the button.
- A paid organization cannot start a second checkout (`:already_subscribed`); it changes
  or cancels its plan in the portal.
- Stripe sends the customer back to `/settings/billing?checkout=done`. Until the webhook
  arrives, the page says the payment is being confirmed, with a "Check again" button
  (`router.reload()`); then "Your new plan is active". Cancel returns to the plain page.
- Product copy: one `billing.plan.<plan>` and one `billing.plan_summary.<plan>` per plan,
  one `billing.interval.<interval>` and `billing.per.<interval>` per interval.

## Customer portal

`POST /settings/billing/portal-session` → `Billing.create_portal_session/2` → Stripe's
hosted portal (card, invoices, cancel), back to the app afterwards. Configure the portal in
the Stripe dashboard (Settings → Billing → Customer portal): allow cancellation at period
end, allow card updates, show invoices. Do not allow plan switching there unless the
product's offers match the portal's products.

## Environment

| Variable | Example | Meaning |
|---|---|---|
| `BILLING_ENABLED` | `true` | Turns billing on. Anything else: off (routes answer 404). |
| `BILLING_MODE` | `test` / `live` | Which keys and prices to use. Default `test`. |
| `BILLING_RENEWAL_NOTICES` | `true` | Sends renewal notices (see above). Default off. |
| `BILLING_TEST_OPERATOR_USER_IDS` | `uuid1,uuid2` | Test mode: who may check out besides superadmins. |
| `STRIPE_TEST_SECRET_KEY` / `STRIPE_LIVE_SECRET_KEY` | `sk_test_…` / `sk_live_…` (or a restricted `rk_…`) | Only the key of the current mode is read. |
| `STRIPE_TEST_WEBHOOK_SECRET` / `STRIPE_LIVE_WEBHOOK_SECRET` | `whsec_…` | The signing secret of the webhook endpoint. |
| `STRIPE_<MODE>_PRICE_<OFFER_ID>` | `STRIPE_LIVE_PRICE_PRO_MONTHLY=price_…` | The Stripe price of each offer (offer id in upper case). |

Secrets live in `cred` (macOS Keychain), never in a file in the repo. Store them once:

```sh
cred add <app>/STRIPE_TEST_SECRET_KEY
cred add <app>/STRIPE_TEST_WEBHOOK_SECRET
cred add <app>/STRIPE_LIVE_SECRET_KEY
cred add <app>/STRIPE_LIVE_WEBHOOK_SECRET
```

Local development: `cred env <app>/STRIPE_TEST_SECRET_KEY --file .env` (and the webhook
secret), then `BILLING_ENABLED=true` and the `STRIPE_TEST_PRICE_*` ids in your shell.

## Deploy

One switch at the top of `config/deploy.yml` (ERB) turns billing on for a deployment:

```ruby
billing = "off"            # "off", "test" or "live"
billing_prices = { "PRO_MONTHLY" => "price_…", "PRO_YEARLY" => "price_…" }
billing_test_operator_user_ids = ""   # test mode: who may pay besides superadmins
billing_renewal_notices = false
```

From it, the ERB writes `BILLING_ENABLED`, `BILLING_MODE`, `BILLING_RENEWAL_NOTICES`,
`BILLING_TEST_OPERATOR_USER_IDS` and `STRIPE_<MODE>_PRICE_<OFFER_ID>` into `env.clear`, and
the two secret names of the mode into `env.secret`. With `"off"` nothing is written.

**The guard.** Every `kamal` command evaluates the ERB first. With billing on, it stops with
a clear message when `.kamal/secrets` lacks the key or webhook secret of the mode, or when a
price is still `price_CHANGE_ME`. A typo in the switch stops it too. It runs even with
`SKIP_GATES=1`. Behind it, the production boot check catches the rest (an offer without a
price, a key of the other mode): the new container does not start, the health check fails
and the running version stays.

Steps:

1. **Test mode first.** Set `billing = "test"`, your user id in
   `billing_test_operator_user_ids` and the test price ids. In `.kamal/secrets`, uncomment
   the two `STRIPE_TEST_` lines:

   ```sh
   STRIPE_TEST_SECRET_KEY=$(cred get <app>/STRIPE_TEST_SECRET_KEY | tr -d '[:space:]')
   STRIPE_TEST_WEBHOOK_SECRET=$(cred get <app>/STRIPE_TEST_WEBHOOK_SECRET | tr -d '[:space:]')
   ```

   `tr` removes the newline a keychain value can carry (it breaks a key). `bin/rename`
   writes the app name in these lines. Deploy, pay with a Stripe test card
   (`4242 4242 4242 4242`), and check that the plan shows on `/settings/billing`.
2. **Live.** Set `billing = "live"` and the live price ids, uncomment the two `STRIPE_LIVE_`
   lines, and clear the operator ids. Deploy.
3. **Renewal notices.** Set `billing_renewal_notices = true` once yearly offers are sold.

The `pre-build` hook removes every name in `.kamal/secrets` from the environment of the
gates, so the Stripe keys never reach a test.

## Stripe setup (per mode)

1. Create a product per plan and a recurring price per offer, with the exact amount and
   currency of the offer. Put the price ids in `STRIPE_<MODE>_PRICE_<OFFER_ID>`.
2. Add a webhook endpoint: `https://<host>/webhooks/stripe/events`, API version
   `2025-09-30.clover` (the version `Billing.Stripe` pins). Events:
   `checkout.session.completed`, `customer.subscription.created`,
   `customer.subscription.updated`, `customer.subscription.deleted`, `invoice.paid`,
   `invoice.payment_failed`. Copy its signing secret into `STRIPE_<MODE>_WEBHOOK_SECRET`.
3. Do NOT turn on Stripe Tax for these prices, and turn off Adaptive Pricing in the
   dashboard too.
4. Promotion codes are created in Stripe; the checkout accepts them
   (`allow_promotion_codes`, and no card is needed for a 100 % code).

## Flow

```
/settings/billing (offer cards, "I accept" box, offer revision)
  → POST /settings/billing/checkout-session  checkout[offerId, offerRevision, accepted]
  → Billing.create_checkout_session/3: enabled, key of the mode, operator (test mode),
    no paid plan yet, known offer, same revision, accepted, price id, Stripe price == offer
  → Stripe POST /v1/checkout/sessions (idempotency key per org/user/offer/hour)
  → audit "billing.checkout_started" → redirect to checkout.stripe.com (Inertia: 409)
  → back to /settings/billing?checkout=done (cancel: /settings/billing)
Stripe → POST /webhooks/stripe/events → Billing.receive_event/2 (signature, livemode)
POST /settings/billing/portal-session → Billing.create_portal_session/2 → billing.stripe.com
```

## Tests

Stripe is never called from tests: `config/test.exs` routes the client through
`Req.Test` (`Req.Test.stub(StarterKit.Billing.Stripe, fn conn -> … end)`). A stub that calls
`flunk/1` proves a guard stopped the request. `subscription_fixture(scope, attrs)` stores a
paid `"pro"` subscription for plan and portal tests. `Billing.Webhook.sign/3` builds a valid
`Stripe-Signature` header for webhook tests.
