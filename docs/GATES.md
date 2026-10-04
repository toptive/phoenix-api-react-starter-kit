# Gates

Green before every commit and every push. There is no CI: these ARE the CI.
When a gate fails, fix the code — never weaken the gate, never add a todo list of violations.

## `mix check` (ex_check, `.check.exs`)

| Gate | Command | Catches |
|---|---|---|
| compiler | `mix compile --warnings-as-errors --force` | warnings, **boundary** violations |
| formatter | `mix format --check-formatted` | formatting |
| credo | `mix credo --strict` | style + `credo/rest_actions.ex`, `credo/worker_perform.ex`, `credo/no_regex_attribute.ex` |
| dialyzer | `mix dialyzer` | type errors |
| sobelow | `mix sobelow --config` | security (Brakeman equivalent) |
| mix_audit | `mix deps.audit` | vulnerable Hex packages |
| hex_audit | `mix hex.audit` | retired packages |
| unused_deps | `mix deps.unlock --check-unused` | lockfile hygiene |
| ex_unit | `mix test` | tests, incl. `test/architecture` and typelizer prop validation |
| typelizer | `mix typelizer.check` | generated TypeScript out of date |
| ts_typecheck | `pnpm typecheck` | TypeScript strict |
| eslint | `pnpm lint` | hard-coded colours, literal UI text, direct fetch/axios, hooks rules, catalogue completeness |
| vitest | `pnpm test` | pure functions and HTTP envelope handling |
| playwright | `pnpm e2e` | complete browser journeys against the real kit API |
| pnpm_audit | `pnpm audit --audit-level=high` | vulnerable npm packages |

## Architecture tests (`test/architecture`)

- every controller action authorizes or opts out;
- no `services/`, `poros/`, `errors/`, `forms/` directories;
- raw `json/2` only in `StarterKitWeb.Responses`;
- Oban queues are `default` and `marketing` only;
- every tenant schema has an isolation test;
- web code never touches `Repo`, `Ecto.Query` or changesets;
- React files are kebab-case; every static i18n key exists in the CSV;
- every rendered page exists and every page is rendered;
- every `render_public` page is reachable by the SSR page glob (tests render without SSR, so a
  missing page fails only in production with a 500).

## Where they run

1. `.claude/hooks/architecture-check` — after every Claude edit (compile + boundary, credo on the
   file, architecture tests for controllers/router/workers, `typelizer.gen` for contract files,
   ESLint on React files, locale build on CSV changes). Wired in `.claude/settings.json`.
2. `.githooks/pre-commit` — staged files: format, compile, credo, typelizer.check, architecture
   tests, ESLint, i18n build.
3. `.githooks/pre-push` — `bin/check` (`mix check --no-retry`). A push that only deletes branches skips
   it. The hook unsets Git's repository-local variables first, so tools that run git elsewhere (the
   advisory DB) work.
4. `/deploy` skill and the Kamal `pre-build` hook — `bin/check` again; the build refuses to start on a
   failure.

**Gate stamp.** When `bin/check` passes on a clean tree, it writes the `HEAD` sha to
`<git dir>/mix-check-passed`. The `pre-build` hook skips `mix check` when the stamp equals `HEAD`:
Kamal builds that exact commit, and it already passed. Any new commit or a dirty tree means no
stamp, so the gates run. Prefer this to `SKIP_GATES=1`.

`mix setup` runs `git config core.hooksPath .githooks`.

## Test database per checkout

`config/test.exs` names the test database `starter_kit_test_<hash of the checkout path>` (plus
`MIX_TEST_PARTITION` when set). Each worktree gets its own database, so two worktrees that run
`mix test` at the same time never share rows. `mix test` creates and migrates the database on
the first run. `POOL_SIZE` sets the connection pool size, and `test_helper.exs` never runs more
test cases at once than the pool has connections. Queries wait up to 60 s (`timeout`,
`queue_target` 5 s), so a busy machine does not fail tests. Drop old databases with
`dropdb starter_kit_test_<hash>` when you no longer need them.

## Parallel lanes

Several apps or worktrees can run on one machine. Each checkout sets its own env:

| Variable | Dev | Test |
|---|---|---|
| `PORT` | Phoenix port and the URLs it builds (default 4000) | — |
| `VITE_PORT` | Vite dev server (default 5173) | — |
| `PGDATABASE` | dev database (default `starter_kit_dev`) | — (one database per checkout) |
| `POOL_SIZE` | Repo pool (default 10) | Repo pool and max test cases (default 10) |
| `MIX_TEST_PARTITION` | — | suffix of the test database |

Postgres allows 100 connections. Keep `POOL_SIZE` small (2–5) when several lanes run at once.
`ERL_FLAGS="+S 2:2"` limits the BEAM to two schedulers on a busy machine.

## Browser journeys against the kit API

`pnpm e2e` runs Chromium journeys against a real API; `pnpm e2e:ui` opens the runner.
Install Chromium once with `pnpm exec playwright install chromium`. Playwright owns Vite on
`E2E_BASE_URL` (default `http://localhost:5173`), proxied to `E2E_API_URL`
(default `http://localhost:4100`). Vite listen ports come from the SPA URLs. Reports and traces
live in ignored `frontend/playwright-report/` and `frontend/test-results/`.
No browser API mocks; external Stripe/AI adapters belong to the backend.

Run the Phoenix kit's `bin/e2e` from its checkout for API setup, browser execution, and cleanup.
For a separately managed API, run `pnpm e2e` from the SPA root with the same `E2E_API_DIR`,
`MIX_BUILD_PATH`, and `E2E_PGDATABASE` as the API. The dev mailer uses
Swoosh Local. Global setup clears `/dev/mailbox/clear` using its CSRF form (or verifies the
mailbox is already empty), then fixtures poll `/dev/mailbox/json` filtered by recipient and
link prefix. Override `E2E_MAILBOX_PATH` / `E2E_MAILBOX_CLEAR_PATH` for another kit.
Swoosh has no server-side recipient filter; keeping the mailbox bounded avoids large reads.

`frontend/e2e/backend.ts` is the only per-kit seam. Each backend implements the same interface:
`seedUser(email, admin?)` returns a confirmed account's fresh `{ token, expiresAt, sudoUntil }`;
`expireSudo(sessionId)` expires only that session; `sendOptionalEmail(userId)` queues real
optional mail. Phoenix uses `mix run --no-start --no-compile` with `MIX_ENV=test`, `E2E=1`,
queues disabled, and an isolated database. Its seed pattern inserts a confirmed user and calls `Accounts.generate_api_token/1`; its first
superadmin uses `Accounts.bootstrap_superadmin/1` (the hook behind
`mix starter_kit.admin.bootstrap EMAIL`). Registration remains a real browser journey.
Password setup, onboarding and subsequent business actions go through the API. Set
`E2E_API_DIR` to the Phoenix checkout and `E2E_PGDATABASE` to a name containing `e2e` or `test`;
normal local `PG*` settings apply. Rails/Rust replace this file with their test helper.

Each kit's `bin/check` must own API boot: create/migrate the isolated DB, start the API with local
mail and upstream stubs, wait for `/health`, run the frontend gates and `pnpm e2e`, and stop
the API in an EXIT/INT/TERM trap. Use a standalone browser-server configuration with local
mail and real job execution. If another lane edits the API,
run an immutable snapshot of its committed revision in `/tmp`, with its own build directory,
and point `E2E_API_DIR` there. Start it with `mix run --no-start --no-halt -e` and apply this endpoint override
before `Application.ensure_all_started(:starter_kit)`:

```elixir
endpoint = Application.get_env(:starter_kit, StarterKitWeb.Endpoint)
Application.put_env(:starter_kit, StarterKitWeb.Endpoint,
  Keyword.merge(endpoint, server: true, watchers: [], reloadable_apps: []))
```

The snapshot prevents config/lockfile changes from triggering Phoenix reload failures;
`reloadable_apps: []` alone does not bypass its config-change check. Fixtures never compile.
For a separate local Postgres port, set `PGPORT` for the fixtures and apply the same runtime
Repo `:port` override when migrating and starting Phoenix (its dev config defaults to 5432).
The suite uses one worker and
respects real rate limits. Its final throttling journey asserts a browser 429 and Retry-After toast.

Admin journeys run by default. Without AI configuration, Fill must show `ai_not_configured`
in place; `E2E_AI=1` switches only the Fill assertion to success when the backend provides a
test adapter.

The Phoenix API kit's `bin/e2e` owns the test environment, build path, database lifecycle,
and `STRIPE_API_BASE` override. `E2E_BILLING=1` starts the
Stripe stub and billing-off API in global setup; teardown stops both. Browser API requests
use the real backend.

Defaults: main API `4100`, billing-off API `4101`, main SPA `5173`, billing-off SPA `5174`,
Stripe stub `localhost:4200`. Override with `E2E_API_URL`, `E2E_API_OFF_URL`, `E2E_BASE_URL`,
`E2E_BASE_OFF_URL`, and `E2E_STRIPE_URL`. The kit's `bin/e2e` sets `E2E_VITE_PORT` and
`E2E_BASE_OFF_URL` for its own SPA ports. Playwright starts Vite on each SPA URL's port.

The API and runner share `STRIPE_TEST_WEBHOOK_SECRET`, `STRIPE_TEST_PRICE_PRO_MONTHLY`, and
`STRIPE_TEST_PRICE_PRO_YEARLY`; defaults match the kit's `config/test.exs`. `E2E_STRIPE_OFFERS`
accepts offer fixtures as JSON with `id`, `priceId`, `amountCents`, `currency`, and `interval`.
`E2E_API_DIR`, `MIX_BUILD_PATH`, `E2E_PGDATABASE`, and `PORT` select the kit root, compiled test
build, isolated database, and API port. Rails/Rust implement `startBillingOffApi()` in the
per-kit seam.

`pnpm lint` includes the catalogue audit. To prune unused frontend keys while preserving
backend keys and dynamic/plural families, run `node i18n/scripts/audit.mjs --prune`, review
the CSV diff, then `pnpm i18n:build`.
