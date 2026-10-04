# Gates

Green before every commit and every push. There is no CI: these ARE the CI.
When a gate fails, fix the code — never weaken the gate, never add a todo list of violations.

## `bin/check` (Mix gates via ex_check, then Playwright)

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
| playwright | `bin/e2e` (runs `pnpm e2e`) | browser journeys against the isolated real API |
| pnpm_audit | `pnpm audit --audit-level=high` | vulnerable npm packages |

## Architecture tests (`test/architecture`)

- every controller action authorizes or opts out;
- no `services/`, `poros/`, `errors/`, `forms/` directories;
- raw `json/2` only in `StarterKitWeb.Responses`;
- Oban queues are `default` and `marketing` only;
- every tenant schema has an isolation test;
- web code never touches `Repo`, `Ecto.Query` or changesets;
- React files are kebab-case; every static i18n key exists in the CSV;
- every SPA page is wired in `router.tsx`;
- every generated route action has a caller or a documented external consumer;
- SPA delivery and jobs dashboard routes are excluded from generated API helpers.

## Where they run

1. `.claude/hooks/architecture-check` — after every Claude edit (compile + boundary, credo on the
   file, architecture tests for controllers/router/workers, `typelizer.gen` for contract files,
   ESLint on React files, locale build on CSV changes). Wired in `.claude/settings.json`.
2. `.githooks/pre-commit` — staged files: format, compile, credo, typelizer.check, architecture
   tests, ESLint, i18n build.
3. `.githooks/pre-push` — `bin/check` (`mix check --no-retry`, then `bin/e2e`). A push that only deletes branches skips
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

`bin/check` runs `bin/e2e` after all Mix and frontend gates; pre-push runs the same command.
`mix setup` installs Playwright Chromium. `bin/e2e` creates and migrates `starter_kit_e2e`,
boots `MIX_ENV=test E2E=1` with ordinary DB connections, local mailbox, Turnstile off and AI
unconfigured, then stops its processes and **drops the E2E database on exit**, including failures.
The independent `_build/e2e` prevents E2E compilation from invalidating the request-test build;
it is an ignored cache, safe to delete when the runner is stopped.

Playwright owns Vite on 5174 and a billing-off SPA on 5175, leaving dev's 5173 available.
With `frontend/e2e/stripe-stub.mjs` present, `bin/e2e` sets `E2E_BILLING=1` and
`STRIPE_API_BASE=$E2E_STRIPE_URL/v1/`. Test config does not install the `Req.Test` plug in this
lane. Only `:test` config enables the exact stub origin for redirects; production refuses
`STRIPE_API_BASE`. The stub serves checkout and portal redirects, prices and subscriptions;
its signed webhooks reach the real API and Oban reconciles them. Global setup owns the stub
and a second API with billing off against the same isolated database. All browser API requests
reach Phoenix. Without the stub only the billing-on journeys skip.

| Variable | Purpose/default |
|---|---|
| `E2E` | `1` imports `config/e2e.exs`; runner-owned |
| `E2E_PGDATABASE` | disposable database, must contain `e2e`; `starter_kit_e2e` |
| `E2E_PORT` | main API port; `4100` |
| `E2E_API_URL` | main API origin, set by `bin/e2e` from its port |
| `E2E_API_OFF_URL` | billing-off API origin; `http://localhost:4101` |
| `E2E_VITE_PORT` | main Vite port; `5174`; billing-off defaults to the next port |
| `E2E_BASE_URL` | existing main SPA origin; omit to let Playwright start Vite |
| `E2E_BASE_OFF_URL` | billing-off SPA origin; defaults to port 5175 |
| `E2E_STRIPE_URL` | stub origin without `/v1/`; `http://127.0.0.1:4242` |
| `E2E_STRIPE_OFFERS` | optional JSON offers (`id`, `priceId`, `amountCents`, `currency`, `interval`) |
| `E2E_BILLING` | runner-owned switch: enables billing and stub setup |
| `E2E_AI` | runner sets `0`; `1` expects successful AI Fill with a configured test adapter |
| `E2E_API_DIR` | fixture checkout, defaults to this repo; runner-owned |
| `E2E_MAILBOX_PATH` | mailbox JSON endpoint; `/dev/mailbox/json` |
| `E2E_MAILBOX_CLEAR_PATH` | mailbox clear endpoint; `/dev/mailbox/clear` |

For parallel checkouts, choose distinct databases, API ports, billing-off API ports, Vite ports
and stub origins. When `E2E_BASE_URL` supplies an existing SPA, start both SPA servers yourself.
`PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `POOL_SIZE` and `ERL_FLAGS` also apply to this lane.
Traces and reports live in ignored `frontend/test-results/` and `frontend/playwright-report/`.

`frontend/e2e/backend.ts` is the per-kit fixture seam: `seedUser` creates confirmed accounts
and bearers, bootstraps the first superadmin through `Accounts.bootstrap_superadmin`,
`expireSudo` expires a session, and `sendOptionalEmail` queues mail for the running API.
These use isolated `mix run` processes; global setup clears the mailbox once.

`pnpm lint` includes the catalogue audit. Prune unused keys with
`node i18n/scripts/audit.mjs --prune`, review the diff, then run `pnpm i18n:build`.

## Testing policy

HTTP API tests cover success, validation, unauthorized, forbidden, isolation and multi-endpoint
flows through the real router, bearer plug, policies, database and serializers. Context tests
cover branching behavior only. Playwright covers SPA flows against the real backend; Vitest
covers pure functions and HTTP transport. No isolated serializer or mocked component tests.
