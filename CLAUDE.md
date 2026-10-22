# StarterKit — rulebook

Phoenix 1.8 JSON API + React 19 SPA + shadcn, one Postgres, Oban.
This repository is the **Toptive base template**: every product starts as a copy of it
(`bin/rename`, then [docs/NEW_PRODUCT.md](docs/NEW_PRODUCT.md)).

One Mix project and one root `package.json`; run all frontend commands from the root, with no second package or workspace.

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
  React: `t("ns.key")` (react-i18next). Elixir: `StarterKit.I18n.t/3`,
  validation messages as keys (`"validation.email_format"`). Placeholders: `{{name}}` on both sides.
- Add a key: edit the CSV (English + Spanish), run `pnpm i18n:build`. Fill a new locale with
  `OPENROUTER_API_KEY=… pnpm i18n:translate`. Admins edit any text at runtime in Admin → Texts;
  every deploy syncs new keys without touching admin edits. Details: [docs/I18N.md](docs/I18N.md).
- Emails render in the recipient's locale. API errors: stable English `code` + translated `message`.

## Layout

```
lib/starter_kit/            domain — one boundary per context (accounts, organizations, i18n, legal, audit, billing, privacy)
lib/starter_kit/<ctx>/      schemas, policies (exported), helper modules and workers (private)
lib/starter_kit/*.ex        platform modules: analytics, notifications, mailer, ai, uploads, monitoring
lib/starter_kit_web/        router, REST controllers, serializers, plugs, SEO, SPA delivery
frontend/src/pages/           task-oriented pages (kebab-case paths)
frontend/src/components/ui/   shadcn primitives — OWNED, edit them freely
frontend/src/components/app/  shared app components (FormStepper, FieldHelp, ConfirmDialog, …)
frontend/src/layouts/         public, auth, app (sidebar), settings, admin
frontend/src/api/             HTTP transport, hooks and generated type contract
frontend/e2e/                 browser journeys and per-kit backend fixtures
frontend/scripts/             build and prerendering scripts
frontend/src/styles/theme.css    the only file a product edits to re-skin
i18n/                       translations.csv → locales/*.json, scripts
credo/, test/architecture/  our rules, executable
```

## Backend

### Controllers (STRICT)

- **REST actions only**: `index show create update delete`. Any other verb is a nested
  resource controller: `POST /admin/users/:user_id/impersonation`, not `impersonate`.
  URLs are resource trees, never verbs. (`credo` check `StarterKit.Credo.RestActions`.)
- **Skinny**: authorize → cast params → ONE context call → render through serializers and
  `render_data/3`, `render_collection/4` or `render_error/4` under `/api/v1`.
- **Authorization**: every action calls `authorize!(conn, action, resource)` or
  `skip_authorization(conn)` (public pages). `VerifyAuthorized` fails the request otherwise and
  `test/architecture` fails the build. Policies: one module per schema, deny by default.
- Controllers never touch `Repo`, `Ecto.Query` or changesets (`boundary` + architecture test).
- API controllers live under `controllers/api/v1`, use opaque bearer sessions, and answer JSON
  envelopes. Validation details are field → `{key, message, bindings?}` lists.

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

## OTP, concurrency and runtime rules

Guards: `test/architecture/otp_runtime_test.exs`. A guard sees direct calls only; the rule still
applies through wrappers.

**Capacity and pools**
- **Pool fits the load.** Per env: Repo `pool_size` ≥ sum of Oban queue limits + 4 for web,
  channels and Oban itself (prod: the `POOL_SIZE`/`OBAN_*_CONCURRENCY` values in `config/deploy.yml`). Why: every job and request needs a connection; a short pool turns
  into `DBConnection` queue timeouts that look like a dead app. Set `queue_target`/`queue_interval`
  for bursty envs. Changing a queue limit or `POOL_SIZE` default means checking both. (guard)
- **Every external call has explicit timeouts**: `receive_timeout` (and `connect_options:
  [timeout: …]` for slow hosts). `Req.post(url, json: body, receive_timeout: 15_000, retry: false)`,
  never a bare `Req.post(url)`. Finch already pools per origin; give a provider its own named
  Finch pool (`finch: StarterKit.Finch.Provider`) only when you must tune its size or count.
  Why: a hung provider holds a request process or a queue slot until the timeout.
- **Retries belong to Oban**, not to the HTTP client inside a job: `retry: false` (or `max_retries: 1`).
  Why: Req's 1/2/4 s sleeps hold a queue slot and a lease while they wait.

**Processes**
- **No HTTP, LLM, file or slow DB work in `handle_call/3` of a named singleton.** Why: one slow
  call blocks every caller of that process. Do the work in the caller, in
  `Task.Supervisor.async_nolink(StarterKit.TaskSupervisor, fn -> … end)` + `Task.yield(task, 5_000) || Task.shutdown(task)`,
  or in a per-entity process (`Registry` + `DynamicSupervisor`, idle timeout). (guard)
- **A singleton that owns data answers the question, not the whole state.** Reply with the
  query result (`{:free_slots, filters}`), not a full snapshot; keep the decoded state in the process
  (load once in `init/1`, persist on change) or in ETS. Why: copying MBs per call and decoding
  per read is CPU-bound and serializes readers behind writers.
- **No `:infinity` timeouts** in `GenServer.call`, `Task.await`, `Agent.get`. Use a finite timeout
  and handle the exit. (guard)
- **Bounded mailboxes.** A process that receives events at a producer's rate must drop, coalesce
  or batch (e.g. keep the latest preview, flush every 250 ms). Check `Process.info(pid, :message_queue_len)`
  in telemetry. Never `cast` work to a singleton faster than it can finish it.
- **ETS tables are created in `init/1` of a supervised process** (`read_concurrency: true` for
  read-heavy, `:public, write_concurrency: true` when writers must not serialize through the
  owner). Why: a table dies with its owner; an unsupervised owner loses the cache. (guard)
- **Periodic work** = Oban Cron, or ONE supervised ticker (`Process.send_after` in `init/1` and
  `handle_info`). Never a timer per request, per row or per event. Every periodic job selects
  only the columns it needs (no large encrypted blobs to read a status).

**Database**
- **No DB transaction or row lock across HTTP/LLM calls.** Read → release → call → write in a
  new short transaction. Why: the connection and the locks stay held for seconds, and every
  other request waits. (guard: no HTTP client call inside `Repo.transact`/`Repo.transaction`)
- **Locks are short and last.** A per-tenant lock (`FOR UPDATE`, hash chains, counters) is the
  LAST statement of its transaction, or moves off the hot path (append unlocked, chain in a
  batch job). `FOR UPDATE` only for writes, never for reads.
- **State that must survive a restart lives in Postgres.** Process state is a cache; a
  restarted conversation reloads from the DB and the client re-joins.
- **Leases and claims have a short TTL and are renewed**, and released in `terminate/2`
  (trap exits). Why: a killed process must not hold a lease for minutes.

**Oban**
- **Queues per workload.** Latency-critical work (a user waits for it) gets
  its own queue, separate from fan-out, sync, marketing and delivery workers.
- **Lifeline `rescue_after` ≤ 15 min** and above the longest job timeout; Pruner is on.
  Why: a hard kill leaves jobs `executing`, and `unique` with `:executing` blocks re-inserts. (guard)
- **No tight reschedule loops.** No `{:snooze, 1}` polling for another job's result; wait in the
  owning process on PubSub with `receive … after`, or run the fetch inline with a timeout.
- **Every worker sets `timeout/1`** below Lifeline's `rescue_after`. Why: a job without a
  timeout can hold a queue slot and a connection forever.
- `unique` periods are finite, or `states` excludes `:executing` where a re-run is safe.

**PubSub, Channels, Presence**
- **No broadcast storms.** Never broadcast per row or per token on a wide topic.
  Ephemeral data (stream deltas, typing) goes on the narrowest topic (`<resource>:<id>`) as a
  non-persisted payload; persist and broadcast domain events only for state changes.
- **Channels do not re-authorize per event.** Authorize on join and on a periodic timer
  (cached in assigns); `handle_info({:domain_event, e}, socket)` only pushes.
- **The client debounces invalidations** (≥ 1 s trailing) and lists ignore detail-only events.
- **Stream LLM replies to the client over the Channel**, chunked (≥ 250 ms or by sentence).
  Persist only the final message.

**Runtime and operations**
- **Health is cheap.** `GET /health` runs no context code: at most `SELECT 1` with a ≤ 2 s
  timeout. Never sessions, plugs with DB work, or the code reloader in front of it. (guard)
- **Dev and QA logging is quiet.** Logger level `:info`; Repo query logs off unless `REPO_LOG=debug`;
  log to a file, never `| tee` into a terminal. Why: the default handler is one process and
  switches to `:sync`, so every logging process waits for stdout. A shared QA box runs
  without the code reloader (`QA=1` or `MIX_ENV=prod`).
- **Named nodes** (`--sname`) everywhere, so `:recon`/`observer_cli` can attach. Use
  `:recon.proc_count(:message_queue_len, 10)`, `:recon.proc_window(:reductions, 10, 1000)` and
  telemetry (Repo queue time, Oban job duration, Endpoint duration) before guessing.
- **Load smoke before "done".** A realtime or chat flow is done only after a smoke run with
  ≥ 2 users and ≥ 3 concurrent conversations: Repo queue time p95 < 50 ms, no mailbox > 1,000,
  and reply p95 within the product target.
- **Stop gracefully.** Watchdogs send `System.stop/0` (SIGTERM), not `kill -9`.

## Type contract

Serializers (`lib/starter_kit_web/serializers`) and the router → `mix typelizer.gen` →
`frontend/src/api/generated/{serializers,routes}`. Generated files are committed;
`mix typelizer.check` fails on drift (pre-commit, pre-push, `/deploy`).
Use generated serializer types and route helpers in the SPA; never mirror a server type or
hard-code a path. The pages generator is disabled. Details: [docs/TYPE_CONTRACT.md](docs/TYPE_CONTRACT.md).

## Frontend

- React 19, TypeScript strict, Vite, Tailwind v4; one SPA in `frontend/`.
- TanStack Router guards wait for bootstrap; React Query loads data only through `@/api/hooks`.
  No `useEffect` for data, no `fetch`/`axios` outside `src/api/http.ts`.
- Forms use react-hook-form + Zod schemas in `src/schemas`; map server field errors using their
  i18n keys. Keep `FormStepper`, `FieldHelp` and `ConfirmDialog`.
- Serializer types and API route helpers live in `frontend/src/api/generated/`; the backend
  generator owns them. Never add hand-written mirror response types.
- **We own the components.** Edit `components/ui` for app-wide changes; repeated patterns live
  in `components/app`. Theme tokens only; new colours go in `frontend/src/styles/theme.css`.
- Admin Jobs opens the ticket URL returned by the API and appears only with `app.jobsDashboard`.
- Files and folders are kebab-case (generated files follow the generator). Pages mirror resources:
  `pages/<resource>/<action>.tsx`. Every UI string comes from `i18n/translations.csv`.

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

`bin/check` runs the following gates through `mix check`, then isolated Playwright journeys
through `bin/e2e`: compile (`--warnings-as-errors`, `boundary`), format,
`credo --strict` (+ our checks), dialyzer, sobelow, `deps.audit`, `hex.audit`, unused deps,
`mix test` (incl. `test/architecture`), `mix typelizer.check`, `pnpm typecheck`, `pnpm lint`,
`pnpm test`, `pnpm audit --audit-level=high`.

- **There is no CI.** Four layers: `.claude/hooks/architecture-check` (after each Claude edit),
  `.githooks/pre-commit` (staged files), `.githooks/pre-push` (`bin/check`), `/deploy` (again).
  `mix setup` installs the hooks. Details: [docs/GATES.md](docs/GATES.md).
- Tests guard a risk; there is no rule that every function or page has one. Skip tests that repeat
  another test, check copy text, or only mirror the code. Keep the suite fast (about 10 s).
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
| SEO | [docs/SEO.md](docs/SEO.md) | prerendering, meta tags, sitemap, robots |
| Platform modules | [docs/PLATFORM.md](docs/PLATFORM.md) | analytics, notifications, AI, uploads, monitoring |
| Billing | [docs/BILLING.md](docs/BILLING.md) | Stripe offers, checkout, webhooks, test vs live keys (OFF by default) |
| Security | [docs/SECURITY.md](docs/SECURITY.md) | reviews, findings, verified-safe areas |
| Gates | [docs/GATES.md](docs/GATES.md) | every check, hooks |
| Performance | [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | memory budget, BEAM tuning, Lighthouse |
| Deploy | [docs/DEPLOY.md](docs/DEPLOY.md) | Kamal, image, env, hooks |
| New server | [docs/NEW_SERVER.md](docs/NEW_SERVER.md) | preparing the product server |
| New product | [docs/NEW_PRODUCT.md](docs/NEW_PRODUCT.md) | from template to product |
