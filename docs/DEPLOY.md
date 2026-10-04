# Deploy

Kamal 2 to the Toptive product server ([NEW_SERVER.md](NEW_SERVER.md)). Use the `/deploy`
Claude skill: it runs every gate, shows what changed, asks for confirmation and deploys.

## Image

`Dockerfile`, two stages:

1. **builder** — `hexpm/elixir` + the Node binary + pnpm: `mix deps.get`, `pnpm install`,
   `pnpm build` (Vite client → `priv/static/assets`, SSR → `priv/ssr/ssr.js`), pre-compress
   static files, `mix release`.
2. **runner** — Debian slim + the release + the `node` binary only + `tini`. User `nobody`.

Kamal builds from a clean clone of the committed `HEAD`: uncommitted changes never ship.

## Building on an Apple-silicon Mac

The products droplet is x86_64, so `builder.arch: amd64`. Docker (OrbStack or Docker Desktop)
cross-builds the image under emulation: it works, the first build is slow (Elixir deps and the
Vite build run emulated), later builds reuse the layer cache. Faster option: a remote x86
builder (`builder.remote: ssh://root@<builder>`), a separate machine — never the products
droplet, whose 4 GB belong to the apps.

Under QEMU the BEAM JIT crashes with its default dual-mapped code memory. `builder.args`
passes `ERL_FLAGS: "+JMsingle true +S 2:2"` to the Dockerfile `ARG ERL_FLAGS`; it applies only to
the build stage, never to the running app.

## Boot: migrations, then the server

The container command is `/app/bin/launch` (`servers.web.cmd`): `bin/migrate` (migrations, then
the i18n sync), then `bin/server`. Kamal uploads the role env before it starts the container, so
this works on the very first `kamal setup` too (a `pre-deploy` hook that runs `kamal app exec`
fails there: the env file does not exist yet). If a migration fails, the container stops, the
health check fails and Kamal keeps the old version serving. Ecto takes a database lock, so two
hosts never migrate at the same time.

Keep migrations backward compatible: the old version keeps serving while the new one migrates.

`rel/env.sh.eex` names the node `starter_kit@127.0.0.1` (long names). Kamal hostnames have dots,
and a short name would cut them, so `kamal console` (`bin/starter_kit remote`) could not connect.

## Hooks

| Hook | Does |
|---|---|
| `.kamal/hooks/pre-build` | `bin/check` (`mix check`) WITHOUT the production secrets (every name in `.kamal/secrets` is removed from its env, so a failing test cannot print one); refuses to build on a failure. It skips the gates when the gate stamp equals `HEAD`: `bin/check` (pre-push, `/deploy`) already passed on that exact clean commit. `SKIP_GATES=1` only for local image experiments |

There is no `pre-deploy` hook: migrations run at boot (above).

## Configuration

`config/deploy.yml` (replace every `CHANGE_ME`): server IP, domain (`proxy.host`, `PHX_HOST`),
`builder.arch` (`amd64`: the droplet is x86_64; on an Apple-silicon Mac the build is
cross-compiled, see below), bucket. The registry is local
(`localhost:5555`, pushed over SSH), so no registry account is needed.

Secrets: `.kamal/secrets` holds references only. Each line reads the value from the macOS
Keychain with `cred` (`NAME=$(cred get starter_kit/NAME | tr -d '[:space:]')`); store a value
with `cred add starter_kit/NAME`. `tr` removes the trailing newline or space that breaks a key, a
token or a Base64 value. A name without a value gives a blank secret, and `runtime.exs` treats a
blank value as unset (a blank `SENTRY_DSN` is also removed from the OS env, because the Sentry
library reads it by itself). Decode a Base64 secret with `Base.decode64(v, ignore: :whitespace)`.

| Variable | Required | Notes |
|---|---|---|
| `SECRET_KEY_BASE` | yes | `mix phx.gen.secret` |
| `DATABASE_URL` | yes | `ecto://<app>:<password>@postgres:5432/<app>` (shared Postgres on the `kamal` network) |
| `POSTMARK_API_KEY` | for email | without it no mail leaves: sign-up, sign-in links, email changes and invitations refuse with a message, and queued mail waits |
| `SENTRY_DSN` | no | error monitoring off without it |
| `OPENROUTER_API_KEY`, `FAL_KEY`, `GOOGLE_API_KEY` | per product | AI features |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | no | Google sign-in |
| `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | for uploads | with `S3_BUCKET`, `S3_ENDPOINT`, `S3_REGION` in `env.clear` |
| `POSTHOG_API_KEY` | no | analytics adapter; needs `POSTHOG_HOST` in `env.clear` (`https://us.i.posthog.com` or `https://eu.i.posthog.com`, the PostHog project's region; boot fails without it) |
| `TURNSTILE_SITE_KEY`, `TURNSTILE_SECRET_KEY` | for bot protection | the `turnstile` switch at the top of `deploy.yml` (default `false`); [AUTH.md](AUTH.md#bot-protection-turnstile) |
| `STRIPE_<MODE>_SECRET_KEY`, `STRIPE_<MODE>_WEBHOOK_SECRET` | for billing | the `billing` switch at the top of `deploy.yml` (default `"off"`); `cred get` lines and steps in [BILLING.md](BILLING.md#deploy) |

Clear env: `PHX_HOST`, `APP_NAME`, `POOL_SIZE` (8), `SITE_INDEXING` (`0` until launch, [SEO.md](SEO.md)), `SIGNUP_MODE` (`invite` until launch, then `open`; [AUTH.md](AUTH.md#sign-up-modes)), `OBAN_*_CONCURRENCY`, `SSR_POOL_SIZE` (1),
`MAIL_FROM`, `MAIL_FROM_NAME` (per locale: `MAIL_FROM_ES`, `MAIL_FROM_NAME_ES`), `S3_*`. Optional: `SSR=0` disables SSR, `ERL_AFLAGS` for BEAM flags,
`POSTMARK_TRANSACTIONAL_STREAM` (`outbound`) / `POSTMARK_BROADCAST_STREAM` (`broadcast`).
**Staging and previews: set `MAIL_ALLOWED_RECIPIENTS`** (`qa@toptive.co,*@toptive.co`): mail to any
other address is dropped and logged, so test data never emails a real person. Leave it unset in
production.

## First deploy of a product (runbook)

Facundo runs these (servers are read-only for Claude):

1. On the server, once per product: the database and its role ([NEW_SERVER.md](NEW_SERVER.md) §5).
2. DNS: point `proxy.host` at the server (Cloudflare: DNS only until the certificate is issued).
3. `config/deploy.yml`: replace every `CHANGE_ME`; check `TRUSTED_PROXY_CIDRS` with
   `docker network inspect kamal` on the server.
4. Secrets, locally: `cred add starter_kit/SECRET_KEY_BASE` (value from `mix phx.gen.secret`),
   `cred add starter_kit/DATABASE_URL`, then the optional ones (`POSTMARK_API_KEY`, …).
   `cred ls starter_kit` shows what is stored.
5. `bin/check` on a clean `main` (writes the gate stamp), then `kamal setup`. The container
   migrates at boot, so the first deploy needs nothing else.
6. Check: `curl -fsS https://<host>/health` answers `ok`; `kamal logs` shows `Migrated` and no
   errors.
7. Create the first superadmin with the bootstrap task ([ADMIN.md](ADMIN.md#first-superadmin)).
8. Launch day: `SITE_INDEXING: "1"` ([SEO.md](SEO.md)) and `SIGNUP_MODE: open`
   ([AUTH.md](AUTH.md#sign-up-modes)), then `kamal deploy`.

If `kamal setup` stops at the health check, read `kamal app logs`: a failed migration or a
missing required secret stops the boot before the server starts.

## Every deploy

`/deploy` (skill) or, by hand: `mix check && kamal deploy`. Useful: `kamal logs`,
`kamal console`, `kamal migrate`, `kamal rollback <version>`, `kamal app details`.

Never run `priv/repo/seeds.exs` against production.

## Timeouts behind kamal-proxy

`Bandit.HTTPError: Read timeout` lines can appear in the logs with no failed request. They come
from idle pooled connections that kamal-proxy keeps open (kamal-proxy 0.9 sets no idle timeout
for them), and Bandit closes them after its read timeout. No visitor sees an error. Change
nothing; look again only if `/health` checks or real requests fail. (Investigated on a product in
2026-10: four such lines, zero failed requests.)
