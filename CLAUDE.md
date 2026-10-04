# StarterKit — rulebook

Phoenix 1.8 JSON API + React 19 SPA + shadcn, one Postgres, Oban.
This repository is the **Toptive base template**: every product starts as a copy of it
(`bin/rename`, then [docs/NEW_PRODUCT.md](docs/NEW_PRODUCT.md)).

One Mix project and one `package.json` at the root. Frontend commands run from the root:
`pnpm dev` (started by `mix phx.server`), `pnpm build`, `pnpm typecheck`, `pnpm lint`,
`pnpm test`, `pnpm i18n:build`. Never add a second `package.json` or a workspace.

## Non-negotiables

- **This file is the rulebook, not a log.** Never add dated notes, progress, or "what changed"
  here. Knowledge about an area goes in its `docs/<AREA>.md`. A rule changes only when the
  architecture decision changes — and that is a conversation with Facundo first.
- **No plans, trackers, status or research documents in the repo.** `docs/` holds reference
  documentation for developers only.
- **Everything is English**: code, comments, docs, commit messages.
- **Tenant isolation.** Every tenant row carries `organization_id`; every query on it runs with
  `org_id:` (the Repo raises otherwise). Every tenant schema has an isolation test.
- **The serializer is the type contract.** Data sent to React goes through a typelizer
  serializer; TypeScript types and route helpers are GENERATED. Never a
  hand-written mirror type, never a hard-coded path.
- **Gates are green before every commit and push.** Fix the code, never the gate.
- **Servers are read-only for Claude.** Give Facundo the exact commands; never run them.

## Language rules (STRICT)

- **UI text is never hard-coded.** `i18n/translations.csv` (`key,en,es`) is the only source.
  React: `t("ns.key")` (react-i18next). Elixir: `StarterKit.I18n.t/3`, `put_flash_t/3`,
  validation messages as keys (`"validation.email_format"`). Placeholders: `{{name}}` on both sides.
- Add a key: edit the CSV (English + Spanish), run `pnpm i18n:build`. Fill a new locale with
  `OPENROUTER_API_KEY=… pnpm i18n:translate`. Admins edit any text at runtime in Admin → Texts;
  every deploy syncs new keys without touching admin edits. Details: [docs/I18N.md](docs/I18N.md).
- Emails render in the recipient's locale. API errors: stable English `code` + translated `message`.

## Layout

```
lib/starter_kit/               domain — accounts, organizations, i18n, legal, audit, billing, privacy
lib/starter_kit/<ctx>/         schemas, policies (exported), helper modules and workers (private)
lib/starter_kit/*.ex           platform modules: analytics, notifications, mailer, ai, uploads, monitoring
lib/starter_kit_web/           router, REST controllers, serializers, plugs, SEO, SPA delivery
frontend/src/pages/            SPA pages organized by resource (kebab-case paths)
frontend/src/components/ui/    shadcn primitives — OWNED, edit them freely
frontend/src/components/app/   shared app components (FormStepper, FieldHelp, ConfirmDialog, …)
frontend/src/layouts/          public, auth, app (sidebar), settings, admin
frontend/src/api/generated/    typelizer output — never edit
frontend/src/styles/theme.css  the only file a product edits to re-skin
i18n/                         translations.csv → locales/*.json, scripts
credo/, test/architecture/     our rules, executable
```

## Backend

### Controllers (STRICT)

- **REST actions only**: `index show new create edit update delete`. Any other verb is a nested
  resource controller: `POST /admin/users/:user_id/impersonation`, not `impersonate`.
  URLs are resource trees, never verbs. (`credo` check `StarterKit.Credo.RestActions`.)
- **Skinny**: authorize → cast params → ONE context call → render through serializers and
  `render_data/3`, `render_collection/4` or `render_error/4` under `/api/v1`.
- **Authorization**: every action calls `authorize!(conn, action, resource)` or
  `skip_authorization(conn)` (public pages). `VerifyAuthorized` fails the request otherwise and
  `test/architecture` fails the build. Policies: one module per schema, deny by default.
- Controllers never touch `Repo`, `Ecto.Query` or changesets (`boundary` + architecture test).
- API controllers live under `controllers/api/v1`, use opaque bearer sessions, and answer JSON
  envelopes. Validation details are field → `{key, message, bindings?}` lists. No Inertia declarations.

### Contexts (STRICT)

- Contexts own ALL business logic. No `services/`, `poros/`, `errors/` or `forms/` anywhere.
- Helper modules live under their context and are called only by it: `boundary` exports only
  the context module, its schemas and its policies.
- Context functions that touch tenant data take `%Scope{}` first.
- Multi-step writes: `Repo.transact/1` with `with`. Every sensitive change: `Audit.record/2`.

### Jobs (STRICT)

- Oban. `perform/1` is ONE context call (`credo` check `StarterKit.Credo.WorkerPerform`).
- Queues `default` and `marketing` only. Recurring work: `Oban.Plugins.Cron` in `config.exs`.
- No Redis. Cachex/ETS and Channels only when a product needs them.

### Conventions

- UUID primary keys, money as integer cents (`amount_cents`), ISO-8601 dates and timestamps.
- The wire is camelCase both ways: props and JSON go out camelized; incoming keys are converted
  to snake_case by `SnakeCaseParams`.
- JSON (`/api/v1`): `{ "data": …, "meta": … }` / `{ "error": { "code", "message", "details" } }`.
- Unauthenticated endpoints that do work carry a rate limit (`Plugs.RateLimit`).

## Type contract

Serializers (`lib/starter_kit_web/serializers`) and the router → `mix typelizer.gen` →
`frontend/src/api/generated/{serializers,routes}`. Generated files are committed;
`mix typelizer.check` fails on drift (pre-commit, pre-push, `/deploy`).
Use generated serializer types and route helpers in the SPA; never mirror a server type or
hard-code a path. The pages generator is disabled. Details: [docs/TYPE_CONTRACT.md](docs/TYPE_CONTRACT.md).

## Frontend

- React 19, TypeScript strict, Vite, Tailwind v4. SPA data uses React Query through the API
  client and generated contract. No raw fetch in pages or useEffect for data.
- Forms use the shared mutation pattern; never react-hook-form.
- **We own the components.** All shadcn primitives live in `components/ui`; change a look
  app-wide by editing the component. Repeated patterns become `components/app/*`
  (never copy-paste between pages).
- **Theme tokens only**: `bg-primary`, `text-muted-foreground`… Never `text-blue-500` or `#hex`
  (ESLint fails). New colours are new tokens in `frontend/src/styles/theme.css`.
- All files and folders kebab-case. Pages mirror controllers: `pages/<resource>/<action>.tsx`.

## UX rules

1. **Users are not techies.** Plain words, no jargon; technical detail goes behind a disclosure.
2. **Screens follow user tasks, not database tables.** Combine models when the user thinks of
   them as one thing (People = members + invitations).
3. **Multi-step forms by default** (`FormStepper`) for anything beyond a few fields: one
   question per step, progress, back, a review step.
4. **Explain in place** (`FieldHelp`): why we ask, what to write. Every state says the next step.
5. **Destructive actions confirm** (`ConfirmDialog`) and say the consequence in plain words.
6. Mobile first; tap targets ≥ 44 px; visible focus (the highlighter ring); reduced motion respected.

## Security

- Policies + tenant guard on every endpoint; superadmin area returns 404 to everyone else.
- Bearer sessions (magic link, password ≥ 12, Google), sudo mode for email/password/account
  changes, rate limits, CSP with nonces, HSTS in production, append-only audit log.
- Uploads only through `StarterKit.Uploads` (allow-lists, size caps, byte sniffing, no SVG).
- Sentry off without a DSN; no request bodies, cookies or PII except the user id.
- Findings live in [docs/SECURITY.md](docs/SECURITY.md). A sobelow false positive is skipped
  ONE at a time, with the reason next to it.

## Testing & gates

`mix check` runs every gate: compile (`--warnings-as-errors`, `boundary`), format,
`credo --strict` (+ our checks), dialyzer, sobelow, `deps.audit`, `hex.audit`, unused deps,
`mix test` (incl. `test/architecture`), `mix typelizer.check`, `pnpm typecheck`, `pnpm lint`,
`pnpm test`, `pnpm audit --audit-level=high`.

- **There is no CI.** Four layers: `.claude/hooks/architecture-check` (after each Claude edit),
  `.githooks/pre-commit` (staged files), `.githooks/pre-push` (`mix check`), `/deploy` (again).
  `mix setup` installs the hooks. Details: [docs/GATES.md](docs/GATES.md).
- Test behavior through HTTP API requests: success, validation, unauthorized, forbidden and tenant
  isolation outcomes, plus end-to-end flows. Context tests cover real branching only; no tests of
  private helpers, standalone serializers or trivial getters. Every tenant schema has an isolation test.
- SPA flows use Playwright against the real backend; Vitest covers pure functions only.

## Deploy

Kamal to the Toptive product server (one shared Postgres, one database per app). Use the
`/deploy` skill: it runs every gate first and refuses to build on a failure. Migrations and the
i18n sync run at boot (`bin/launch`), before the server starts. Never run seeds against production.
Details: [docs/DEPLOY.md](docs/DEPLOY.md), [docs/NEW_SERVER.md](docs/NEW_SERVER.md).

## Domain documents

| Area | Doc | Owns |
|---|---|---|
| Architecture | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | boundaries, controllers, policies, jobs, responses |
| Type contract | [docs/TYPE_CONTRACT.md](docs/TYPE_CONTRACT.md) | typelizer, generated TS |
| Auth | [docs/AUTH.md](docs/AUTH.md) | sign-in, sessions, sudo mode, impersonation, rate limits |
| Tenancy | [docs/TENANCY.md](docs/TENANCY.md) | organizations, roles, invitations, tenant guard |
| i18n | [docs/I18N.md](docs/I18N.md) | CSV, runtime catalogue, admin editor, sync |
| Admin | [docs/ADMIN.md](docs/ADMIN.md) | superadmin area, legal documents, audit log |
| Design system | [docs/DESIGN.md](docs/DESIGN.md) | tokens, components, layouts, UX |
| SEO | [docs/SEO.md](docs/SEO.md) | SSR, meta tags, sitemap, robots |
| Platform modules | [docs/PLATFORM.md](docs/PLATFORM.md) | analytics, notifications, AI, uploads, monitoring |
| Billing | [docs/BILLING.md](docs/BILLING.md) | Stripe offers, checkout, webhooks, test vs live keys (OFF by default) |
| Security | [docs/SECURITY.md](docs/SECURITY.md) | reviews, findings, verified-safe areas |
| Gates | [docs/GATES.md](docs/GATES.md) | every check, hooks |
| Performance | [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | memory budget, BEAM/SSR tuning, Lighthouse |
| Deploy | [docs/DEPLOY.md](docs/DEPLOY.md) | Kamal, image, env, hooks |
| New server | [docs/NEW_SERVER.md](docs/NEW_SERVER.md) | preparing the product server |
| New product | [docs/NEW_PRODUCT.md](docs/NEW_PRODUCT.md) | from template to product |
