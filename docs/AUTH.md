# Authentication

The SPA uses the JSON API under `/api/v1`, opaque bearer sessions, and generated serializer
and route types. `StarterKit.Accounts` owns identity, emailed tokens, sessions and impersonation.
`StarterKit.Organizations` coordinates sign-in with the initial organization and builds bootstrap.

## Bootstrap and translations

`GET /api/v1/bootstrap` is public. `Bootstrap.auth` is null for anonymous callers; otherwise
`Auth` carries the user, current organization, membership (`user: null`), accessible organizations,
superadmin/impersonator, `onboardingRequired`, `sudoUntil` and `sessionId`. The remaining fields
are locale, supported locales, i18n version, public app configuration, flags and Turnstile.
`app.publicUrl` is the configured SPA origin. Bootstrap is private, no-store.

`GET /api/v1/locales/:locale` returns the flat catalogue and `meta: {locale, version}`. Dictionary
keys retain their spelling. Unsupported locales return 404. The strong ETag is `"<locale>:<version>"`;
`Cache-Control: public, no-cache` requires revalidation. A matching `If-None-Match` returns an
empty 304. Locale precedence is query, Accept-Language, signed-in user's locale, then English.

## Auth endpoints

All bodies are flat camelCase JSON. A field error is `{key, message, bindings?}`, with a translated
message and bindings only when the translation has placeholders. Every error has
`{error: {code, message, details}}`; unknown message keys fall back to `errors.api.internal_error`.

| Method | Resource | Result |
|---|---|---|
| POST | `/api/v1/auth/registrations` | Name, email, termsAccepted, optional locale/turnstileToken → 202 `MagicLinkRequest {email, newAccount: true}` |
| POST | `/api/v1/auth/magic-links` | Email, optional turnstileToken → 202 `MagicLinkRequest {email, newAccount: false}`, including unknown addresses |
| GET | `/api/v1/auth/magic-links/:token` | Non-consuming `MagicLink {email, confirmed}` preview |
| POST | `/api/v1/auth/magic-links/:token/session` | Single-use confirmation/sign-in → 201 `AuthSession` |
| POST | `/api/v1/auth/sessions` | Email/password → 201 `AuthSession`; any credential failure is 401 `invalid_credentials` |
| DELETE | `/api/v1/auth/session` | Revoke the current bearer → empty 204 |
| POST | `/api/v1/auth/sudo` | Password OR magicLinkToken → `SudoWindow {sudoUntil}` |
| GET | `/api/v1/auth/google/start` | Optional client=web/native and returnTo → 302 to Google |
| GET | `/api/v1/auth/google/callback` | Signed state/code → 302 web/native handoff |
| DELETE | `/api/v1/auth/impersonation` | End impersonation while retaining the admin token → empty 204 |

`AuthSession` has nullable `token`, `expiresAt`, nullable `sudoUntil`, `user`, nullable
`impersonator` and `newAccount`. Password or magic-link sign-in with a valid bearer for the same
user refreshes that session's sudo window and returns `token: null`. The SPA keeps its token.
A first magic-link sign-in confirms the address, expires the user's other emailed tokens, and
sets `newAccount: true`. Unknown, expired or spent links return 422 `magic_link_invalid`.
Confirmation happens through magic-link consumption. A forgotten password is handled by signing
in with a magic link and setting a new password in settings.

Registration commits the user, published terms/privacy acceptances with client IP and
`user.registered` audit event together. Refusals happen before writes: 422 `signup_closed` or
`invitation_required`, 503 `email_unavailable`, and 422 `turnstile_failed`. Without email delivery,
magic-link requests and invitations also refuse; password sign-in continues to work. Emails to
users use their saved locale. `SIGNUP_MODE` is open, invite or closed; invalid configuration stops
boot. Existing accounts can sign in in every mode.

## Sessions and emailed tokens

The API accepts only `Authorization: Bearer <token>` and never sets cookies. Each token contains
32 random bytes encoded as 43 base64url characters. `sessions.token_hash` is SHA-256 of the encoded
bearer; plaintext tokens are returned once. Sessions contain user, current organization,
authenticated_at, sudo_until, expires_at, last_used_at, revoked_at, truncated user_agent, resolved
ip_address, and impersonator_user_id/impersonator_session_id/impersonation_id when applicable.

Upgrading from the legacy token table signs out existing sessions; emailed magic-link and email-change
tokens are retained with their renamed contexts.

Sessions expire after fourteen days. A request with fewer than seven days remaining extends the
expiry to fourteen days from now; another extension cannot occur until that window elapses.
`last_used_at` changes at most once per minute. Missing or unknown bearers give 401 `unauthorized`
on protected routes; known expired or revoked bearers give 401 `session_expired`, including on
public routes. Organization selection belongs to the device session; see [TENANCY.md](TENANCY.md).

Emailed tokens live in `user_tokens`: a digest, user, context, recipient and insertion timestamp.
Contexts are `magic_link` (15 minutes) and `change_email:<old address>` (7 days). They are single
use. The daily `Accounts.TokenCleanupWorker` removes expired emailed tokens and sessions whose
expiry or revocation is more than thirty days old.

## Sudo and impersonation

Sign-in starts a ten-minute sudo window. `BearerAuth.require_sudo/2` returns 403 `sudo_required`
when that window is absent or expired. Sudo reauthentication refreshes only this device:
password failure gives 401 `invalid_credentials`; a passwordless user's password attempt gives
422 `validation_failed` on password (`validation.required`). A magic link must belong to the
same user, or the request gives 422 `magic_link_invalid` without consuming the other user's link.

Impersonation uses a separate session with no sudo window. Sudo returns 403 `forbidden`.
`DELETE /auth/impersonation` revokes it, ends its impersonation record and audits the stop; the SPA
restores the admin token it saved. A normal session gets 409 `conflict` when trying to stop
impersonation. Signing out while impersonating revokes both sessions. Revoking an administrator
session also revokes impersonation sessions it started. Superadmin privileges are absent while
impersonating.

## Google OAuth

Configure Google's redirect URI as API origin + `/api/v1/auth/google/callback`. Both routes
return 404 while Google is disabled. Start validates client and a returnTo SPA path (starts with
`/`, at most 200 characters, no `//`), then signs state containing nonce, client, returnTo, locale
and iat. State expires in 600 seconds. The Google URL uses `openid email profile` and
`prompt=select_account`. No OAuth cookie is issued.

Callback verifies state, exchanges code and requires a verified email before linking by Google
uid/email or creating an account. Signup rules apply to new accounts, with no legal acceptance
because Google has no consent checkbox. Handoff is configured, never an arbitrary request URL:

- Web: `SPA_ORIGIN/auth/callback#token=<token>&expiresAt=<iso>&new=<0|1>&returnTo=<encoded path>`.
- Native: `NATIVE_SCHEME://auth/callback` with the same fragment.
- Failure: `#error=oauth_failed|email_not_verified|invitation_required|signup_closed|state_invalid`.

The fragment keeps the bearer out of server request logs and Referer. Callback responses use
`Referrer-Policy: no-referrer`. `SPA_ORIGIN` and `CORS_ORIGINS` are required at production boot;
local development defaults to localhost:5173. CORS also allows capacitor://localhost,
ionic://localhost and http://localhost, with no credentials and no PATCH.

## Rate limits and bot protection

| Resource | Limit per resolved client IP |
|---|---|
| Sessions, registrations, magic-link consumption | 10/min each |
| Magic-link requests, sudo | 5/min each |
| Google callback | 20/min |
| Invitations | 30/hour |
| Invitation acceptance | 10/min |
| Email opt-out | 120/min |

Over-limit responses are 429 `rate_limited`, with both `Retry-After` and `details.retryAfter`.
All errors are private, no-store and noindex. Turnstile is off by default. When enabled, registration
and magic-link requests must pass the expected action/hostname before writes. Refusal is 422
`turnstile_failed`, with `details.turnstileToken` field errors using `validation.turnstile_required`.
Bootstrap exposes only the required flag and public site key.

`ClientIp` trusts X-Forwarded-For only from configured proxies and CF-Connecting-IP only from a
Cloudflare hop. Device IP, rate limits and audit events use that resolved peer. Sensitive account
settings use sudo; account deletion locks organizations and preserves consent/billing history
according to `StarterKit.Privacy`.
