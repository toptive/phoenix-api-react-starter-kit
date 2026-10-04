---
name: deploy
description: Deploy this app to production with Kamal. Runs every gate first and refuses to build on a failure, shows what changed since the live version, asks for confirmation, deploys, and verifies. Use when the user says deploy, ship, release to production, or kamal deploy.
---

# Deploy

Servers are read-only for Claude **except** through `kamal deploy` after the user confirms in
this conversation. Never run other state-changing commands on the server (no SSH edits, no
seeds, no `kamal setup` — the first deploy is the user's, see docs/DEPLOY.md).

## Step 0 — gates (MANDATORY)

```sh
bin/check
```

`mix check` includes `mix typelizer.check`: the generated TypeScript (types, routes, page props)
must match the serializers, router and page declarations. It needs the dev database up.

If ANY gate fails: stop. Report the failing gate and its output. Do not deploy "just this once",
do not skip a gate, do not use `--no-verify` or `SKIP_GATES`. Fix the code or hand back to the user.

## Step 1 — what is going out

```sh
git status --porcelain            # must be empty: deploy only committed code
git rev-parse --abbrev-ref HEAD   # must be main
git fetch -q && git status -sb    # must not be behind origin/main
LIVE=$(kamal app version -q 2>/dev/null | tail -1)
git log --oneline "$LIVE"..HEAD
git diff --stat "$LIVE"..HEAD -- priv/repo/migrations i18n/translations.csv config/deploy.yml config/runtime.exs
```

Summarise for the user: commits, new migrations (and whether they lock big tables), i18n keys
added, env/config changes (a new secret must exist in their shell before deploying). Then ask:
"Deploy <sha> to <host>?" — wait for an explicit yes.

## Step 2 — deploy

```sh
kamal deploy
```

The `pre-build` hook skips the gates when Step 0 left the gate stamp for this `HEAD`, and runs
them otherwise. The new container runs migrations and the i18n sync at boot (`bin/launch`),
before it takes traffic.
If the deploy fails, show the output; offer `kamal rollback <previous version>` and wait for the user.

## Step 3 — verify

```sh
HOST=$(kamal config | awk '/host:/{print $2; exit}')
curl -fsS "https://$HOST/health"                      # "ok"
curl -fsS -o /dev/null -w "%{http_code}\n" "https://$HOST/"       # 200, server-rendered
curl -fsS "https://$HOST/" | grep -c 'data-server-rendered\|<h1'  # SSR produced HTML
curl -fsS "https://$HOST/sitemap.xml" | head -5
kamal app details
kamal app logs --since 5m | grep -iE "error|exception" | tail -20
```

Report: version live, checks passed, anything odd in the logs. Mention any gate exception or
skipped step explicitly.
