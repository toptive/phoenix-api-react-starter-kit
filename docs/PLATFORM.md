# Platform modules — one call site each

| Need | Call | Module |
|---|---|---|
| Product analytics | `Analytics.track("user_signed_in", user, %{method: "password"})` | `StarterKit.Analytics` |
| Feature flags | `Flags.enabled?(:billing)`; React `useSharedProps().flags.billing` | `StarterKit.Flags` |
| Tell a person something | `Notifications.notify(user, :magic_link, %{url: url})` | `StarterKit.Notifications` |
| LLM | `AI.chat(messages)`, `AI.translate_strings(map, from: "en", to: "es")` | `StarterKit.AI` (OpenRouter) |
| Image/audio/video models | `AI.fal("fal-ai/flux/schnell", %{prompt: …})` | `StarterKit.AI` (fal.ai) |
| Gemini | `AI.gemini(prompt)` | `StarterKit.AI` (Google) |
| File uploads | `Uploads.presign/2`, `Uploads.verify/2`, `Uploads.url/2`; React `uploadFile(file, kind)` | `StarterKit.Uploads` |
| Error monitoring | automatic; `Monitoring.report(exception, context)` for rescued errors | `StarterKit.Monitoring` (Sentry) |

## Feature flags

Every on/off switch is declared once in `StarterKit.Flags`: its env var, its default, and
`public: true` when React may see it. `config/runtime.exs` reads the env vars; code asks
`Flags.enabled?(:billing)` (an unknown name raises). Public flags reach every page as the
`flags` shared prop, typed by typelizer (`flags.billing`); the others never leave the server.

| Flag | Env | Default | Public |
|---|---|---|---|
| `:billing` | `BILLING_ENABLED` | off | yes |
| `:billing_renewal_notices` | `BILLING_RENEWAL_NOTICES` | off | no |
| `:site_indexing` | `SITE_INDEXING` | on (production: off until launch) | no |
| `:turnstile` | `TURNSTILE_REQUIRED` | off | no (the `turnstile` shared prop, [AUTH.md](AUTH.md#bot-protection-turnstile)) |

**Boot guard.** A flag that needs a setup gets a readiness check in
`StarterKit.Application` (`Flags.check!(billing: &Billing.config_problems/0, turnstile: …)`). In production
(`check_on_boot: true`) a flag that is ON but not ready stops the boot and lists every problem,
so a half-configured feature never reaches a customer.

**Add a flag**: a line in `@flags`, its default in `config/config.exs`, the env var in
`config/runtime.exs` and `config/deploy.yml`, a readiness check if it needs keys, then
`mix typelizer.gen` when it is public.

**Tests** never `Application.put_env` a flag: `put_flag(:billing, false)` (setup or test body)
or `with_flag(:billing, false, fn -> … end)`. The value holds for the test process and the
processes it starts, so the test stays `async: true`.

## Analytics

Events and their property rules are listed in `StarterKit.Analytics.Events`; an unknown
event raises in dev/test and is dropped in production. Every property is typed: one of a list
of values, `:boolean`, `{:count, max}`, `{:slug, max}` (letters, digits, `_ . -`: never an
email or a URL) or `{:path, max}` (a public page path, no query). A value that breaks its rule
is dropped, and so is an undeclared property. Adapters: `:log` (default), `:posthog`
(`POSTHOG_API_KEY`), `:test`. Client events go through `POST /api/v1/events` and must be
marked `origin: :client`; an unknown client event is ignored.

Delivery never blocks a request: at most 8 sends run at once (the rest are dropped), with short
timeouts and no retry. Every event carries `$geoip_disable: true` (the IP would be the server's).

**After commit.** Track a write after its transaction, never inside it (a rollback would leave
an event for something that did not happen):
`Repo.transact(…) |> Analytics.track_after_commit("onboarding_completed", scope, props)` tracks
only on `{:ok, _}` and returns the result unchanged.

**The default funnel** (keep the names, so the same PostHog funnel works in every product):
`user_registered` → `signup_confirmed` → `onboarding_completed` → `checkout_started` →
`subscription_started` (→ `subscription_canceled`). The starter sends all of them;
`subscription_*` come from the Stripe webhook (no user: an anonymous count). `signup_started`
is in the catalogue for a product with a longer sign-up form.

`POSTHOG_HOST` is required with the key and has no default: the project's region decides it,
`https://us.i.posthog.com` (US cloud) or `https://eu.i.posthog.com` (EU cloud, for EU data
residency). An event without a user (`nil` actor) is anonymous: a throwaway random
`distinct_id` per event and `$process_person_profile: false`, so PostHog builds no person profile.

Public pages are tracked server-side by `Plugs.PageViews` (the `:page_views` pipeline):
`public_page_viewed` with the page type (`home.show`), locale, path, referrer host and `utm_*`.
No script, no IP and no visitor id leave the app, and the plug adds no cookie and no response
header: it never makes a cookie-free, cacheable public page (a product's HTML cache) stop being one. Crawlers, prefetches, Inertia partial
reloads and non-200 responses are skipped. Pipe a new public scope through `:page_views`.

## Notifications and mail

`notify/3` queues an Oban job (queue `default`); the worker renders the email in the recipient's
locale and sends through Swoosh. Mailer adapters: `Local` in dev (`/dev/mailbox`), `Test` in tests,
`Postmark` in production (`POSTMARK_API_KEY`; without it the Logger adapter).

**One branded layout for every email** (`Notifications.Email`), structure and not prose:
logo header (`/images/mail/logo.png`, built by `bin/icons`) → headline → one short lead → a facts
block (label/value rows) → ONE button → at most two short muted notes → footer with the reason for
the email, plus "Email preferences" / "Unsubscribe" links when the data has `preferences_url` /
`unsubscribe_url` (`:optional` kinds only). `test: true` in the data puts a
"Test mode" badge above the headline. Colours: `config :starter_kit, :mail_brand`; links and the
logo use `config :starter_kit, :public_url` (jobs have no request URL).

**Groups** (`@kinds` in `Notifications`): `:access` (sign-in, email change) and `:transactional`
(invitations, renewals) are always sent and never show unsubscribe links; `:optional` (lifecycle,
marketing, e.g. `product_update`) gets the unsubscribe link, `List-Unsubscribe` and the Postmark
broadcast stream. Postmark never tracks opens or links.

**One-click unsubscribe (RFC 8058), any Swoosh adapter.** Optional mail to a user gets
`unsubscribe_url` from `notify/3` itself: `/email-subscriptions/:token/opt-out`, a token signed with
`secret_key_base` over the user id and a hash of the address (no expiry; it stops working when the
address changes). The email carries `List-Unsubscribe: <url>` and, for an https URL,
`List-Unsubscribe-Post: List-Unsubscribe=One-Click`. Mail clients POST there with no session or
CSRF token (`:one_click` pipeline) and get a bare 200; the footer link opens the same URL as a page
with one button (scanners only GET). Unsubscribing sets `users.optional_emails = false`, is
idempotent, is audited once (`user.optional_emails_stopped`) and is rate limited (120/min per IP:
providers POST from shared IPs). `notify/3` then returns `{:ok, :opted_out}` for optional kinds;
access and transactional mail still go out. The same mail also gets `preferences_url`: Settings →
Email notifications (`/settings/email-preferences/edit`), where the user turns optional mail back on
(`Accounts.update_email_preferences/2`, audited as `user.optional_emails_started` / `_stopped`); the
"You are unsubscribed" page links there. A recipient that is not a user must pass its own
`unsubscribe_url` (`notify/3` raises otherwise). With Postmark, set the broadcast stream's
unsubscribe handling to your own links, so Postmark does not add a second unsubscribe link.

**Email gallery (dev only).** `/dev/emails` lists every kind; `/dev/emails/<kind>?locale=es` shows
the subject, sender, headers (`List-Unsubscribe`, Postmark stream), the HTML at desktop and phone
width, and the text part. It renders `Notifications.preview/2` with sample data and sends nothing.
A new kind whose copy uses a new `{{binding}}` adds a sample value to `@preview_data`
(`email_layout_test.exs` fails otherwise). Sent dev mail stays in `/dev/mailbox`.

**Sender per locale.** `Mailer.from(locale)`: `MAIL_FROM_ES` / `MAIL_FROM_NAME_ES` (`ZH_HK` for
`zh-HK`) give Spanish recipients their own From; a locale without them uses `MAIL_FROM` /
`MAIL_FROM_NAME`. Every address must be a verified sender at the provider.

**Delivery fails closed.** `email_available?/0` is false without a real adapter (production with
no `POSTMARK_API_KEY`): the job snoozes for an hour (never a silent drop), and the actions that
only exist to send mail (sign-up, sign-in links, email change, invitations) refuse before any
write. `MAIL_ALLOWED_RECIPIENTS` (staging, previews) cancels mail to any other address and logs
the domain only.

Add a kind: add it with its group to `@kinds`, its facts rows to `@facts` in `Notifications.Email`, and the
keys `mail.<kind>.subject`, `.headline`, `.lead`, `.action` (optional `.note1`, `.note2`,
`.footer`; labels `mail.fact.<label>`) to the CSV. Keep sentences under ~20 words, no raw URLs in
the copy, never mention tax. `test/starter_kit/email_layout_test.exs` renders every kind in every
locale and fails without the layout; it also fails if any other module builds mail.

## AI

Toptive rule: OpenRouter for LLMs, fal.ai for media, Google for Gemini/TTS — never the OpenAI or
Anthropic SDKs directly. Keys and models from the environment (`OPENROUTER_API_KEY`,
`OPENROUTER_MODEL`, `FAL_KEY`, `GOOGLE_API_KEY`, `GEMINI_MODEL`). A missing key returns
`{:error, :not_configured}`; there is no silent fallback. Tests swap the HTTP layer
(`StarterKit.AI.FakeHTTP`).

## Uploads

1. React: `const key = await uploadFile(file, "image")` (`lib/uploads.ts`) → `POST /api/v1/direct-uploads`.
2. `UploadGuard` checks the kind, the content type allow-list and the size cap, then the server
   returns a 10-minute presigned PUT URL under `uploads/<organization_id>/…`.
3. The browser PUTs the file to storage; the form submits the key.
4. The owning context calls `Uploads.verify(key, kind)` (size + byte sniffing) before saving it.
5. Objects are private; read them with `Uploads.url(key)` (5-minute presigned GET).

Kinds: `image` (JPEG/PNG/WebP/GIF, 10 MB), `document` (PDF/JPEG/PNG, 20 MB), `avatar` (2 MB).
SVG is never accepted. Storage: any S3-compatible service (`S3_*` env; DigitalOcean Spaces by default).
The CSP allows `connect-src` to the storage host.

## Monitoring

Sentry is off unless `SENTRY_DSN` is set. It captures plug errors, crashed processes and Oban job
failures. No request bodies, no cookies, no authorization headers; the only personal data is the
user id.
