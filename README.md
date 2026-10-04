# Toptive Phoenix API + React starter kit

Phoenix 1.8 JSON API, React 19 SPA, TypeScript, TanStack Router and React Query, Tailwind v4,
owned shadcn components, Oban and one PostgreSQL database.

Includes bearer sign-in (magic link, password, Google), organizations and invitations,
runtime translations, admin tools, billing, audit logging, direct uploads, generated API types
and route helpers, prerendered landing pages, sitemap/robots and Kamal deployment.
Billing is off by default; configure Stripe using [docs/BILLING.md](docs/BILLING.md).

## Start

Requirements: Elixir 1.19 / OTP 28, Node 22, pnpm, PostgreSQL 17.

```sh
mix setup          # deps, pnpm, Chromium, git hooks, database, seeds
mix phx.server     # API on localhost:4000; starts Vite on localhost:5173
```

Open http://localhost:5173 for the SPA during development. Vite proxies `/api` to Phoenix.
`VITE_PORT`, `PORT` and `VITE_DEV_API_URL` configure parallel local apps.
Seeded users: `admin@example.com` / `password1234` and `member@example.com` / `password1234`.
Development emails: http://localhost:4000/dev/mailbox.

`pnpm build` writes the SPA and prerendered public pages to `priv/static`; Phoenix serves
that output in production. `bin/check` runs every backend and frontend gate through `mix check`,
then isolated Playwright journeys through `bin/e2e`, including billing against a local Stripe stub.
E2E uses Vite on 5174 (billing-off on 5175), its own `_build/e2e`, and drops its database on exit,
so it can run alongside `mix phx.server`. `E2E_VITE_PORT` selects another browser port.

`docker build -t starter-kit:local .` builds the complete SPA and Phoenix release. Typelizer is
vendored until its route naming options are on Hex; no sibling checkout is required.
See [docs/DEPLOY.md](docs/DEPLOY.md) for the disposable Postgres smoke command and runtime env.

## Documentation

[CLAUDE.md](CLAUDE.md) is the rulebook (`AGENTS.md` links to it).
Start a product with [docs/NEW_PRODUCT.md](docs/NEW_PRODUCT.md).
