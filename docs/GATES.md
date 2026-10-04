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
| eslint | `pnpm lint` | hard-coded colours, literal UI text, react-hook-form/axios/fetch, hooks rules |
| vitest | `pnpm test` | frontend unit tests |
| pnpm_audit | `pnpm audit --audit-level=high` | vulnerable npm packages |

## Testing policy

Prefer end-to-end behavior through the public surface. Backend request tests use the real HTTP
router, bearer plug, policies, database, serializers and envelope. Cover each endpoint's success,
validation, unauthorized, forbidden and tenant isolation outcomes, and chain endpoints in flow
tests. Context tests are reserved for real branching such as money, dates, policies and parsers.
Do not test private helpers, standalone serializers or trivial getters.

SPA user flows use Playwright in `frontend/e2e/` against the real backend. Vitest covers pure
functions such as envelope parsing and date/money formatting; no component render tests with
mocked APIs. Architecture tests continue to guard the rulebook and remain part of `mix test`.

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
