# Authentication

The auth area is a JSON API under `/api/v1/auth`, consumed by the SPA. Context:
`StarterKit.Accounts`. Authentication: `StarterKitWeb.Plugs.BearerAuth`. Unconverted browser
areas still use `StarterKitWeb.UserAuth` and cookie sessions until their area is converted.

## Sign up and sign in

Requests use flat camelCase fields (`email`, `password`, `passwordConfirmation`,
`termsAccepted`, `turnstileToken`). Responses use `{data, meta}` or
`{error: {code, message, details}}`; validation failures are 422 `validation_failed`, with
field names mapped to lists of i18n message keys.

| Method | Resource | Behavior |
|---|---|---|
| POST | `/api/v1/auth/sessions` | Email/password → 201 `{token, expiresAt, user}` |
| DELETE | `/api/v1/auth/session` | Revokes only the current bearer token; requires authentication |
| POST | `/api/v1/auth/registrations` | Name/email/terms; sends an SPA magic link; no bearer issued |
| POST | `/api/v1/auth/magic-links` | Emails a link; identical response for known and unknown emails |
| POST | `/api/v1/auth/magic-links/:token/session` | Consumes a single-use link → 201 session payload |
| POST | `/api/v1/auth/confirmations/:token` | Confirms email and consumes the link; no bearer issued |
| POST | `/api/v1/auth/password-resets` | Private reset request; identical response for unknown emails |
| PUT | `/api/v1/auth/password-resets/:token` | Sets password; revokes all tokens; single-use, fifteen-minute link |
| POST | `/api/v1/auth/sudo` | Checks the current user's password; returns `{sudoUntil}` |
| GET | `/api/v1/auth/current-user` | Requires a bearer and authorizes access to the user |
| GET | `/api/v1/auth/google/start` | 302 to Google with signed, browser-bound state |
| GET | `/api/v1/auth/google/callback` | 302 to `SPA_ORIGIN/auth/callback#token=…` or `#error=…` |

The sign-up user, legal consent and `user.registered` audit event are written in one
transaction. Consent covers the published terms/privacy versions and the resolved client IP.
Google sign-up has no checkbox, so it does not record legal acceptance. Google must verify
the email before linking or creating an account; signup modes apply to new accounts.
Configure Google's redirect URI as the API origin plus `/api/v1/auth/google/callback`.

`spa_origin` (`SPA_ORIGIN`, default `http://localhost:5173`) builds emailed auth links and OAuth
redirects. Magic links open `/auth/magic-links/:token` in the SPA, where the user's button
POSTs the token. GET never consumes a magic link. Reset links open `/auth/password-resets/:token`.
Emails still render in the recipient's preferred locale. Passwords are at least twelve characters.

Without a delivery adapter, registration, magic-link requests and reset requests refuse with
503 `email_unavailable` before writing. Password sign-in still works. Bootstrap exposes
`app.emailAvailable`, `app.googleEnabled` and `app.signupMode` so the SPA can explain availability.

## Bearer tokens

Send `Authorization: Bearer <token>` on API requests. The random 32-byte token is URL-safe
base64; only its SHA-256 hash is stored in `users_tokens` under context `api`. The row carries
`expires_at` (fourteen days), `sudo_until` (ten minutes), device/IP and `impersonator_id`.
The bearer plug loads the user and row, then resolves the current organization through
membership and `last_organization_id`. It assigns `current_user`, `current_scope`, `api_token`.
Cookies never authenticate an API request. Missing, malformed, expired or revoked tokens are
anonymous; protected resources return 401 `unauthorized`. Tokens are not automatically rotated.
Sign-out revokes the current token; password reset revokes every token and confirms the email.
Password reset and sudo reauthentication record `user.password_reset` and
`user.sudo_authenticated`, respectively, in the same transaction as the change.

Google state is signed, valid for ten minutes, and bound to a transient HttpOnly SameSite=Lax
cookie. This is an OAuth flow cookie, not an authentication session. Tokens return in the SPA
fragment so they never enter the SPA server's request URL. Callback responses are private and
send `Referrer-Policy: no-referrer`. Both Google credentials must be configured.

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
## Devices during conversion

API tokens record user agent and resolved client IP. The unconverted Settings → Devices
controller still lists cookie sessions; it will adopt API token rows when that area is converted.

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

API sensitive resources use `BearerAuth.require_sudo/2`, returning 401 `sudo_required`
when the current token's ten-minute window has expired. `POST /api/v1/auth/sudo` verifies a
password and extends this token only. A passwordless user can sign in again with a magic link
to receive a fresh token with a sudo window. Impersonated tokens cannot enter sudo mode.
Unconverted browser settings keep `UserAuth.require_sudo_mode/2` and redirect to SPA sign-in.

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

| API resource | Limit |
|---|---|
| Password sessions, registrations, magic-link sessions, confirmations | 10 / minute each |
| Magic-link requests, password resets | 5 / minute each |
| Sudo, Google start, Google callback | 10 / minute each |
| Direct uploads | 60 / minute |
| Analytics events | 120 / minute |

Anonymous endpoints that create work are limited. Exceeded limits return 429 `rate_limited`
and a `Retry-After` header. Error responses are private, no-store and noindex.

## Bot protection (Turnstile)

Turnstile guards API registration and magic-link requests. It is OFF by default (`turnstile`
flag, `TURNSTILE_REQUIRED`). The flat `turnstileToken` must pass the expected action and
hostname; failure returns 422 `validation_failed`, with
`details.turnstileToken: ["validation.turnstile_required"]`, before any action runs.
Bootstrap exposes only `turnstile.required` and the public `siteKey`. Emailed link consumption
needs no new challenge. See [SECURITY.md](SECURITY.md) for provider and proxy setup.

The client IP comes from `StarterKitWeb.Plugs.ClientIp`. `X-Forwarded-For` counts only when the
socket peer is in `TRUSTED_PROXY_CIDRS` (kamal-proxy's Docker network), and `CF-Connecting-IP`
only when the hop before kamal-proxy is a Cloudflare edge (`priv/network/cloudflare-cidrs.txt`,
refresh with `mix starter_kit.cloudflare.refresh`). Anyone else's headers are ignored, so a
visitor cannot pick their own rate-limit bucket or audit IP. Audit events take this IP
automatically (`Audit.put_request_ip/1`).

Google sign-in requires Google's `email_verified` claim: an unverified Google email is refused,
so nobody can link a Google account to another person's address.
