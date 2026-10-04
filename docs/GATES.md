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

Prefer end-to-end behavior tests: backend requests exercise the real router, auth, policies,
database and serializers; SPA journeys use Chromium in `frontend/e2e/`. Vitest is for pure
functions and HTTP envelope handling. Do not render components against mocked APIs.
The browser suite never intercepts or replaces `/api/v1` responses. External services such
as Stripe and AI are stubbed at the backend's upstream HTTP boundary.

Install once with `pnpm exec playwright install chromium`. Run `pnpm e2e` from the root;
`pnpm e2e:ui` opens Playwright's UI. Playwright starts and stops Vite on 5173 with a proxy to
`E2E_API_URL` (default `http://localhost:4100`). Setting `E2E_BASE_URL` uses an already running
SPA instead. That SPA must point to the same API. Failure traces and screenshots are in
`frontend/test-results/`; the HTML report is in `frontend/playwright-report/` (both ignored).

The API must be running first. For the Phoenix API kit, the development fallback is:

```sh
cd /path/to/phoenix-api-react-starter-kit
PGDATABASE=starter_kit_e2e mix ecto.create
PGDATABASE=starter_kit_e2e mix ecto.migrate
PGDATABASE=starter_kit_e2e PORT=4100 VITE_PORT=5199 SPA_ORIGIN=http://localhost:5173 MAIL_ADAPTER=local mix phx.server
```

`config/dev.exs` reads `PGDATABASE`, `PORT` and `VITE_PORT`; `runtime.exs` reads `SPA_ORIGIN`.
The dev mailer already uses Swoosh Local (the current kit does not read `MAIL_ADAPTER`).
`/dev/mailbox/json` returns recipient, text and HTML bodies; fixtures poll it to obtain
single-use links. Set `E2E_MAILBOX_PATH` for another kit's equivalent test mailbox. Users,
confirmation, onboarding and password setup all go through generated API routes. Fixtures
respect rate limits and their real `Retry-After`; they create unique addresses per test.

The only direct database fixture adjustments are expiring a test session's sudo window
(to exercise a real 403 without waiting ten minutes) and promoting a test account when
admin journeys are enabled. They use `psql` and `E2E_PGDATABASE` (default `starter_kit_e2e`),
with the normal local `PGHOST`/`PGPORT`/`PGUSER`/`PGPASSWORD` settings. A database name must
contain `e2e` or `test`. Other kits should replace these two fixtures with their test helper;
do not bypass registration or business actions. The unsubscribe journey queues a real optional
notification through the Phoenix public context from a small `mix run --no-start` process
with queues disabled; the running API delivers it to the mailbox. Set `E2E_API_DIR` to that
checkout (default: the sibling Phoenix API kit used during SPA development). Other backend
lanes replace this mail arrangement with their equivalent test helper. The browser still
previews and opts out through the public API.

Each backend lane wires this into its `bin/check` after request tests and frontend gates:
create and migrate a dedicated E2E database; boot the API in test mode on 4100 with the local
mailbox, HTTP stubs and normal DB connections available across requests; wait for `/health`;
run `E2E_API_URL=http://localhost:4100 E2E_PGDATABASE=<isolated-db> pnpm e2e`; stop the API in
an EXIT/INT/TERM trap, including on test failure. A Phoenix test server needs its test
configuration to read the chosen port/database, enable test mailbox routes, start the
endpoint and allow browser requests through its sandbox. The current backend test config
is not yet a standalone E2E server; the commands above run in development until that lane
lands. API boot is deliberately owned by `bin/check`, rather than a SPA script tied to Mix.

Admin journeys (texts edit/fill, impersonation/back, legal publication, audit and Jobs) have
explicit `test.skip` reasons while the Phoenix admin lane is in progress. Set `E2E_ADMIN=1`
when it has landed, with the backend's fake AI HTTP adapter for Fill. Billing checkout and
portal journeys use `E2E_BILLING=1` once the billing API lane supplies Stripe test HTTP stubs
and subscription fixtures. Skips are reported and must be removed or enabled in those lanes.

`pnpm i18n:audit` checks English and Spanish, frontend key references, backend references,
dynamic namespaces and plural variants. `pnpm lint` runs it as a gate. To remove genuinely
unused keys, run `node i18n/scripts/audit.mjs --prune`, review the CSV diff, then
`pnpm i18n:build`. Runtime and backend text must stay in the shared catalogue.
