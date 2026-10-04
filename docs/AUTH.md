# Authentication

Session auth in the `phx.gen.auth` 1.8 style, extended with organizations and impersonation.
Context: `StarterKit.Accounts`. Web: `StarterKitWeb.UserAuth`.

## Sign up and sign in

- **Sign up** (`/registration/new`): name + email + one checkbox (terms and privacy). The user
  gets a magic link; opening it confirms the email and signs in. No password at sign-up (fewer
  steps for non-technical users). Who may sign up: [Sign-up modes](#sign-up-modes).
- **Consent** is written in the same transaction as the user (`Accounts.register_user/3`): one
  `LegalAcceptance` per published version of `terms` and `privacy` (IP kept), plus the
  `user.registered` audit event with the accepted slugs. No account without its consent; the
  link leaves after the commit. An unpublished document is skipped. Google sign-up has no
  checkbox, so it records no acceptance.
- **Magic link** (`/session/new`, "Email me a link"): single use, 15 minutes. The link opens a page
  with one button (`POST /session` with the token), so email scanners cannot consume it. The
  response never reveals whether an email has an account.
- **No mail, no "check your inbox"**: when no mail can leave (`Notifications.email_available?/0`
  is false: production without `POSTMARK_API_KEY`), sign-up, sign-in links and email changes
  refuse before any write and say so (`flash.email_unavailable`). The sign-up and sign-in pages
  get `emailAvailable` (`Accounts.email_sign_in_available?/0`) and say it up front: no sign-up
  form, no link form and no stale "check your email"; password sign-in still works.
- **Password** (optional, Settings → Password): at least 12 characters. A password change ends
  every other session.
- **Google** (optional): set `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`. The button appears on
  the sign-in page. An existing account with the same email is linked.
- **Email change**: the link in the "confirm your new email" message opens a page with one button
  (`GET /settings/email-confirmations/:token`); only the button's `POST` changes the email. The
  token is single-use and needs the user's session, so a link scanner can never use it.
- Remember-me cookie (14 days) is on by default; session tokens are reissued every 7 days.

## Sign-up modes

`SIGNUP_MODE` (`Accounts.signup_mode/0`, default `open`; a wrong value stops the boot):

| Mode | Who may create an account |
|---|---|
| `open` | anyone |
| `invite` | only an email with an open invitation (`Organizations.register_user/3`, `upsert_google_user/1`); others get `flash.invitation_required` |
| `closed` | nobody (`flash.signup_closed`); the sign-in page hides "Create account" |

Existing users sign in in every mode, Google included. Production starts at `invite` in
`config/deploy.yml` (like `SITE_INDEXING`); set `open` on launch day. The first superadmin comes
from the bootstrap task ([ADMIN.md](ADMIN.md#first-superadmin)), not from sign-up.
## Sessions

Each session token stores the device (user agent, IP). Settings → Devices lists them; the user
signs out any device.

## Account deletion

Settings → Delete account (sudo mode) calls `StarterKit.Privacy.delete_account/1`. It locks the
user's organizations first (the same lock as membership changes), then refuses, with nothing
written, when:

- the user is the last owner of an organization that has other people
  (`:transfer_ownership` — make someone else an owner in People first);
- the user is the only person in an organization whose Stripe subscription can still charge
  (`:subscription_active` — any status except `canceled`/`incomplete_expired`, either mode).

The page shows the reason and a link to the place that fixes it (`Privacy.deletion_blocker/1`).
Otherwise the user, tokens and memberships go (FK cascade); legal acceptances stay as proof of
consent. An organization left with nobody in it is deleted with its data, unless it has
billing history, which stays as a record. A product with tenant tables that must outlive the
organization uses `on_delete: :restrict` and handles the orphan in `Privacy`.

## Sudo mode

Email, password and account deletion need a sign-in within the last 10 minutes
(`require_sudo_mode`); otherwise the user is asked to sign in again and comes back.

## Roles

- Global: `User.role` = `:user` or `:superadmin` (the admin area).
- Per organization: see [TENANCY.md](TENANCY.md).

## Impersonation

A superadmin opens Admin → Users → a user → "Act as". A reason is required. The session keeps
the admin's own token aside (`:impersonator_token`); a banner shows during the whole
impersonation; "Back to my account" restores the admin. Start and stop are audit events
(`impersonation.started|stopped`), and every audit event records the impersonator. Superadmins
cannot be impersonated.

## Rate limits (per IP, `Plugs.RateLimit`, ETS)

| Endpoint | Limit |
|---|---|
| `POST /session` | 10 / minute |
| `POST /registration` | 10 / minute |
| `POST /magic-links` | 5 / minute |
| `POST /settings/invitations` | 30 / hour |
| `POST /api/v1/direct-uploads` | 60 / minute |
| `POST /api/v1/events` | 120 / minute |
| `POST /email-subscriptions/:token/opt-out` | 120 / minute (429 JSON: no session) |

Over the limit: a translated flash + redirect back (pages), or 429 in the JSON envelope.

## Bot protection (Turnstile)

Cloudflare Turnstile guards the anonymous forms that create work: sign-up
(`POST /registration`) and "email me a link" (`POST /magic-links`). It is OFF by default
(flag `:turnstile`, env `TURNSTILE_REQUIRED`). The emailed sign-in link stays one click.

- **Server**: `StarterKit.AbuseProtection.verify/3` asks Cloudflare's siteverify and checks
  `success`, our hostname (`TURNSTILE_HOSTNAME`, else `PHX_HOST`) and the action. One try,
  5 s, no retry. Anything else refuses: no token, a used token, a timeout, a missing secret.
- **Plug**: `plug StarterKitWeb.Plugs.VerifyTurnstile, "registration" when action == :create`.
  A refusal goes back to the form with a translated error on `turnstileToken`; the action
  never runs.
- **Page**: `components/app/turnstile.tsx` with the same action. It reads the `turnstile`
  shared prop (`required`, the public site key; never the secret) and renders nothing when
  OFF. A token works once: bump `attempt` after every submit. Every form behind the plug
  must render the widget; `assets/js/components/app/turnstile-forms.test.tsx` checks the two forms.
- **CSP**: `challenges.cloudflare.com` joins `script-src`, `connect-src` and `frame-src`
  only while the flag is ON.
- **New action**: add it to `AbuseProtection.actions/0`, the plug's `form_path/1`, the
  `TurnstileAction` type, and the page test.

Turn it on:

1. Cloudflare dashboard → Turnstile → add a widget for the product's hostname (mode
   "Managed"). Store the keys: `cred add starter_kit/TURNSTILE_SITE_KEY`,
   `cred add starter_kit/TURNSTILE_SECRET_KEY`.
2. Uncomment the two `TURNSTILE_*` lines in `.kamal/secrets` and set `turnstile = true` at
   the top of `config/deploy.yml`.
3. Deploy. In production a missing key or a Cloudflare test key (`1x000…`, `2x000…`,
   `3x000…`) stops the boot.

Dev: `TURNSTILE_REQUIRED=true TURNSTILE_SITE_KEY=1x00000000000000000000AA
TURNSTILE_SECRET_KEY=1x0000000000000000000000000000000AA mix phx.server` (Cloudflare's
always-pass test keys; their answer counts only while the secret is a test secret). Use
`2x00000000000000000000AB` as the site key to see a blocked visitor. Automated browsers
fail real challenges: tests answer for Cloudflare with `Req.Test` (`put_flag(:turnstile, true)`).

The client IP comes from `StarterKitWeb.Plugs.ClientIp`. `X-Forwarded-For` counts only when the
socket peer is in `TRUSTED_PROXY_CIDRS` (kamal-proxy's Docker network), and `CF-Connecting-IP`
only when the hop before kamal-proxy is a Cloudflare edge (`priv/network/cloudflare-cidrs.txt`,
refresh with `mix starter_kit.cloudflare.refresh`). Anyone else's headers are ignored, so a
visitor cannot pick their own rate-limit bucket or audit IP. Audit events take this IP
automatically (`Audit.put_request_ip/1`).

Google sign-in requires Google's `email_verified` claim: an unverified Google email is refused,
so nobody can link a Google account to another person's address.
