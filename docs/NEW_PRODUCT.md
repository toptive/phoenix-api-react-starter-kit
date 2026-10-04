# From template to product

1. **Create the repo**: GitHub → `toptive/phoenix-inertia-react-starter-kit` → "Use this
   template" → private repo named after the product, and clone it.
2. **Rename** (one commit):
   ```sh
   bin/rename --app visa_hub --module VisaHub --name "WH Visas" --domain whvisas.com
   mix setup          # deps, pnpm, git hooks, database, seeds
   mix check          # every gate green before the first commit
   git commit -am "Rename the template to WH Visas"
   ```
   `bin/rename` also regenerates the cookie salts and the dev/test secret keys.
3. **Tenancy**: keep `config :visa_hub, :tenancy, :multi`, or set `:single` for a product with
   one shared organization ([TENANCY.md](TENANCY.md)).
4. **Theme** ([DESIGN.md](DESIGN.md) "Re-skin checklist"): `assets/css/theme.css` tokens, fonts,
   logo, favicon (+ `bin/icons`), social cards (`bin/og-cards.mjs`), `:theme_color`, `:mail_brand`.
   `placeholder_test.exs` fails until the favicon, icons, cards and deploy hosts are your own.
5. **Copy and locales**: landing text and product name in `i18n/translations.csv` (`app.name`,
   `home.*`, `mail.*`); add a locale if needed ([I18N.md](I18N.md) "Adding a locale").
6. **Legal**: write terms, privacy and cookies in Admin → Legal documents and publish them.
7. **Dev port**: pick a free Vite port for this product (`VITE_PORT=5181 mix phx.server`, or put
   it in your shell profile) so several products run side by side.
8. **Product code**: new contexts under `lib/visa_hub/`, REST controllers, serializers, pages.
   Read `AGENTS.md` first. `mix phx.gen.context --scope` generators know the scope.
   Replace the onboarding steps with the product's first-run questions
   ([TENANCY.md](TENANCY.md#onboarding)).
9. **Server**: database + role + bucket on the product server ([NEW_SERVER.md](NEW_SERVER.md) §5, §7),
   DNS records.
10. **Deploy**: fill `config/deploy.yml` (IP, domain, bucket), export the secrets, `kamal setup`,
    then create the first superadmin with the bootstrap task ([ADMIN.md](ADMIN.md#first-superadmin)).
11. **Launch**: set `SITE_INDEXING: "1"` and `SIGNUP_MODE: open` in `config/deploy.yml` and deploy. Until then search
    engines see `noindex` everywhere ([SEO.md](SEO.md) "Indexing lock").
