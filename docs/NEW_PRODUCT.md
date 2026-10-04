# From template to product

1. **Create the repo**: GitHub → `toptive/phoenix-api-react-starter-kit` → "Use this
   template" → private repo named after the product, and clone it.
2. **Rename and install**:
   ```sh
   bin/rename --app visa_hub --module VisaHub --name "WH Visas" --domain whvisas.com
   mix setup          # deps, root pnpm, Chromium, git hooks, database, seeds
   mix format         # the new module name can change Elixir line wrapping
   ```
   Run from the repository root. The module/app names, package name, Docker release path,
   deploy service/image/domain, native scheme, SPA storage prefix and inline appearance
   bootstrap are rewritten together. Cookie salts and dev/test secret keys are regenerated.
   Typelizer is vendored, so no sibling checkout is needed; its source is excluded from rename.
   The script removes `.template-repo`, enabling the product launch checks. **Complete the
   branding step below before `bin/check` and the first commit**: untouched template icons
   and social cards deliberately fail the product gate.
3. **Tenancy**: keep `config :visa_hub, :tenancy, :multi`, or set `:single` for a product with
   one shared organization ([TENANCY.md](TENANCY.md)).
4. **Theme** ([DESIGN.md](DESIGN.md) "Re-skin checklist"): `frontend/src/styles/theme.css` tokens, fonts,
   logo, favicon (+ `bin/icons`), social cards (`bin/og-cards.mjs`), `:theme_color`, `:mail_brand`.
   Replace `priv/static/favicon.svg` with the product mark, then generate the raster assets:
   ```sh
   # macOS prerequisites for branding scripts:
   brew install librsvg imagemagick
   pnpm i18n:build
   bin/icons
   bin/og-cards.mjs
   ```
   The cards read the renamed `app.name` and theme. `placeholder_test.exs` refuses any
   untouched template brand file, name or public-host placeholder. The server IP and bucket
   still need the product's deployment settings; rename does not provision infrastructure.
5. **Copy and locales**: landing text and product name in `i18n/translations.csv` (`app.name`,
   `home.*`, `mail.*`); add a locale if needed ([I18N.md](I18N.md) "Adding a locale").
   After branding and copy changes:
   ```sh
   mix typelizer.gen
   bin/check          # all gates, including isolated browser journeys
   docker build -t visa-hub:local .
   git add -A
   git commit -m "Rename the template to WH Visas"
   ```
   `bin/check` uses Vite 5174/5175, API 4100/4101 and local Stripe 4242, and drops its disposable
   E2E database afterward. Use the `E2E_*` variables in [GATES.md](GATES.md) for parallel products.
   See [DEPLOY.md](DEPLOY.md) for a local image boot with throwaway Postgres and `/health`.
6. **Legal**: write terms, privacy and cookies in Admin → Legal documents and publish them.
7. **Dev port**: pick a free Vite port for this product (`VITE_PORT=5181 mix phx.server`, or set it
   in your shell profile); open the SPA on that Vite port so several products run side by side.
8. **Product code**: new contexts under `lib/visa_hub/`, JSON REST controllers under `controllers/api/v1`, serializers and SPA pages.
   Read `AGENTS.md` first. `mix phx.gen.context --scope` generators know the scope.
   Replace the onboarding steps with the product's first-run questions
   ([TENANCY.md](TENANCY.md#onboarding)).
9. **Server**: database + role + bucket on the product server ([NEW_SERVER.md](NEW_SERVER.md) §5, §7),
   DNS records.
10. **Deploy**: fill `config/deploy.yml` (IP, domain, bucket), export the secrets, `kamal setup`,
    then create the first superadmin with the bootstrap task ([ADMIN.md](ADMIN.md#first-superadmin)).
11. **Launch**: set `site_indexing = "1"` at the top of `config/deploy.yml` (runtime and SPA build)
    and `SIGNUP_MODE: open` and deploy. Until then search
    engines see `noindex` everywhere ([SEO.md](SEO.md) "Indexing lock").
