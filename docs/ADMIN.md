# Admin area

All `/api/v1/admin/` endpoints require a live bearer for a global superadmin, outside
impersonation. Anonymous, ordinary, expired and impersonating callers receive 404. Each action
also authorizes through the existing schema policy. Inputs are flat camelCase JSON; results use
the API envelopes and generated serializers.

## First superadmin

`Accounts.bootstrap_superadmin/1` promotes an existing account or creates a confirmed account
without a password. It refuses once any superadmin exists and records
`user.superadmin_bootstrapped`. The account can sign in with a magic link or Google.

```sh
mix starter_kit.admin.bootstrap you@example.com
```

For production, use the release bootstrap command described in [DEPLOY.md](DEPLOY.md).

## Resources

| Method | Resource under `/api/v1/admin` | Result |
|---|---|---|
| GET | `/dashboard` | `AdminStats` user and organization counts |
| GET | `/users` | Paginated `User[]`; `q` searches email/name, newest first |
| GET | `/users/:id` | `AdminUserDetail` user and their organizations |
| PUT | `/users/:id` | `User`; `role` is `user` or `superadmin`, audits `user.role_changed` |
| POST | `/users/:id/impersonation` | 201 `AuthSession`; reason is 5..255 characters |
| GET | `/organizations` | Paginated `AdminOrganization[]`, name search and member counts |
| GET | `/organizations/:id` | `AdminOrganizationDetail`, memberships with users |
| GET | `/translations` | Paginated `TranslationEntry[]`; `q`, `missing=<locale>`, exact `key=<key>` |
| PUT | `/translations/:key` | `TranslationEntry`; locale/value, max 20,000 characters |
| POST | `/translation-fills` | 201 `TranslationFill`; locale, synchronous AI fill |
| GET | `/legal-documents` | `LegalDocument[]`, ensures terms/privacy/cookies exist |
| GET | `/legal-documents/:slug` | `LegalDocument`, versions newest first |
| POST | `/legal-documents/:slug/versions` | 201 `LegalDocumentVersion`, optional publish |
| POST | `/legal-documents/:slug/versions/:number/publication` | 201 `LegalDocument`, idempotent |
| GET | `/audit-events` | Paginated `AuditEvent[]`, UUID or action search |
| POST | `/jobs-access` | 201 `JobsAccess { url }`, single-use browser handoff |

Paginated responses put `page`, `perPage`, `total`, and `totalPages` under `meta.pagination`.
Queries accept `page` and `perPage` (default 25, maximum 100). Text editing and sync are described
in [I18N.md](I18N.md).

## Impersonation

The target must be an ordinary user, never the administrator or another superadmin. Refusal is
403 `forbidden`. Creation atomically inserts the existing `Accounts.Impersonation` record and
an eight-hour bearer session tied to the originating administrator session. It has no sudo
window and its expiry never slides. `impersonation.started` records reason and impersonation id.

The SPA saves its original admin token separately and uses the returned target token. Bootstrap
shows the target and `auth.impersonator`, with `superadmin: false`. Writes record both actors.
`DELETE /api/v1/auth/impersonation` revokes the target session, ends the record and audits
`impersonation.stopped`; the SPA restores its saved admin token. Signing out while impersonating
revokes both sessions. See [AUTH.md](AUTH.md).

## Legal documents

`StarterKit.Legal` retains numbered, immutable versions. Creation accepts `titles` and `bodies`
as locale maps, with non-empty English required, optional `note` (max 255), and optional boolean
`publish`. Field errors use `validation.english_required`. Creation records
`legal.version_created`; publishing records `legal.published`. Saving and publishing happen in
one transaction. Publishing an already current version leaves the timestamp and audit log intact.

`GET /api/v1/legal-pages/:slug` returns the published `LegalPage` in the request locale, falling
back to English separately for title and body. Unknown or unpublished documents return 404.
Bodies are plain text: blank lines separate paragraphs and `## ` starts a heading. The client
renders text safely. Responses use `Cache-Control: public, no-cache` and the strong ETag
`"<slug>:<number>:<locale>"`; matching conditional requests return an empty 304.
`Legal.accept(scope, slug, ip)` retains consent to the exact version, including after deletion.

## Audit log

Contexts call `Audit.record/2` for sensitive changes. The append-only database trigger rejects
UPDATE/DELETE. The viewer returns newest events first, resolves actor email once per page, and
keeps metadata keys verbatim. A UUID query matches subject or actor id; other queries search the
action case-insensitively. Missing/deleted actors have a null email.

## Oban Web

The dashboard and its assets live under `/admin/jobs`, separate from the SPA. After a bearer
request to `POST /api/v1/admin/jobs-access`, the browser opens the returned URL in a new tab. Issuance audits `admin.jobs_dashboard_opened`; `Bootstrap.app.jobsDashboard` is true.
The JSON response never sets a cookie. Its URL points to `/admin/jobs/session?ticket=…` on the API origin. The signed ticket is valid for 60 seconds and is consumed atomically once. A browser GET exchanges it for a 302 to `/admin/jobs` and sets `_starter_kit_jobs`: signed, HttpOnly, SameSite Strict, restricted to `/admin/jobs`,
Secure on production HTTPS, with a five-minute lifetime. It contains the originating session id;
it never contains the bearer. Cookies do not authenticate the JSON API.

`StarterKitWeb.JobsAccess` verifies signature, age, bearer-session expiry/revocation, current
superadmin role and absence of impersonation on every dashboard/asset request and LiveView
mount. Connected sockets recheck on events, navigation and once per second, so grants stop
working after expiry, demotion or logout. Phoenix's browser session supports LiveView CSRF only;
a browser login session cannot grant jobs access. Oban receives the per-request CSP nonce.
After expiry, request a new grant through the API and reopen the dashboard.

Legal locale titles are capped at 255 characters and bodies at 100,000 characters. Translation filling refuses the default locale with 422 validation_failed. Provider failure returns 503 ai_unavailable. Catalogue versions are deterministic content hashes including row updated_at timestamps, so nodes serving the same catalogue share an ETag.
