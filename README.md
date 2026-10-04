# Toptive Phoenix API + React starter kit

Phoenix 1.8 JSON API, React 19 SPA, TypeScript, TanStack Router and React Query, Tailwind v4,
owned shadcn components, Oban and one PostgreSQL database.

Includes bearer sign-in (magic link, password, Google), organizations and invitations,
runtime translations, admin tools, billing, audit logging, direct uploads, generated API types
and route helpers, prerendered landing pages, sitemap/robots and Kamal deployment.

## Start

Requirements: Elixir 1.19 / OTP 28, Node 22, pnpm, PostgreSQL 17.

```sh
mix setup          # deps, root pnpm install, git hooks, database, seeds
mix phx.server     # API on localhost:4000; starts Vite on localhost:5173
```

Open http://localhost:5173 for the SPA during development. Vite proxies `/api` to Phoenix.
`VITE_PORT`, `PORT` and `VITE_DEV_API_URL` configure parallel local apps.
Seeded users: `admin@example.com` / `password1234` and `member@example.com` / `password1234`.
Development emails: http://localhost:4000/dev/mailbox.

`pnpm build` writes the SPA and prerendered public pages to `priv/static`; Phoenix serves
that output in production. `bin/check` runs every backend and frontend gate through `mix check`.
`pnpm e2e` runs Playwright separately against the real backend.

## Documentation

[CLAUDE.md](CLAUDE.md) is the rulebook (`AGENTS.md` links to it).
Start a product with [docs/NEW_PRODUCT.md](docs/NEW_PRODUCT.md).
