# Toptive Phoenix + Inertia + React starter kit

The base every Toptive product starts from: Phoenix 1.8, Inertia, React 19, TypeScript,
Tailwind v4 and all shadcn components (owned), server-rendered public pages, Oban, one Postgres.
About 105 MB of memory per app at idle, SSR included.

What you get: sign-in (magic link, password, Google), organizations with roles and invitations
(multi or single tenant), every text translatable and editable at runtime (en + es), an admin
area (users, organizations, texts, legal documents, audit log, jobs, impersonation), SEO (SSR,
meta, hreflang, sitemap), a themeable design system, platform modules (analytics, email, AI,
uploads, error monitoring), generated TypeScript types and routes, 14 local gates, and a Kamal
deploy.

## Start

Requirements: Elixir 1.19 / OTP 28, Node 22, pnpm, PostgreSQL 17.

```sh
mix setup          # deps, pnpm install, git hooks, database, seeds
mix phx.server     # http://localhost:4000 (Vite dev server started for you)
```

Seeded users: `admin@example.com` / `password1234` (superadmin), `member@example.com` / `password1234`.
Emails in development: http://localhost:4000/dev/mailbox.

`mix check` runs every gate. `SSR=1 mix phx.server` renders public pages on the server in dev.

## Documentation

Start with [AGENTS.md](AGENTS.md) (the rules; `CLAUDE.md` links to it), then the documents
listed at its end. New product: [docs/NEW_PRODUCT.md](docs/NEW_PRODUCT.md).
