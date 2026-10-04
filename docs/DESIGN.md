# Design system

**A product changes tokens, not components.** Re-skin by editing `frontend/src/css/theme.css` only.

## Default theme: "Paperwork, handled"

The products help non-technical people through forms and documents. The theme reads like calm
paperwork: paper and ink, a seal-green primary for actions and "done", and a highlighter yellow
that marks *where you are* — the focus ring and the current step. One typeface, Public Sans
(a civic, very legible face), self-hosted.

| Token | Light | Use |
|---|---|---|
| `--background` | paper `#F6F8F6` | page |
| `--foreground` | ink `#16222B` | text |
| `--primary` | seal `#11694F` | primary buttons, done states |
| `--highlight` / `--ring` | highlighter `#F3DA5A` | focus ring, current step |
| `--destructive` | `#B4322A` | destructive actions |
| `--border` | `#D9E0DC` | lines |
| `--overlay` | ink at 55 % | behind dialogs |

Plus `card`, `popover`, `secondary`, `muted`, `accent`, `success`, `warning`, `info`,
`chart-1…5`, `sidebar-*`, and a `.dark` set. `--radius` is the control radius; surfaces use
`rounded-xl`, pills `rounded-full`. Colours are OKLCH.

**Rule:** no colour classes from the Tailwind palette and no hex values in components
(ESLint fails). A new colour is a new token here + `@theme inline` in `app.css`. Emails are the
one exception (inline styles, `config :starter_kit, :mail_brand`).

## Layers

| Layer | Folder | Rule |
|---|---|---|
| Primitives | `components/ui/` | every shadcn component, owned — edit them to change a look app-wide |
| App components | `components/app/` | repeated patterns; a pattern used twice moves here |
| Layouts | `layouts/` | chosen by route metadata in `app-shell.tsx`; pages never wrap themselves |
| Pages | `pages/<resource>/<action>.tsx` | one per controller action |

App components: `FormStepper` (multi-step forms with review), `FormField` + `FieldHelp`
(label, help and error wired for screen readers), `ConfirmDialog`, `AlertBanner`, `EmptyState`,
`StatusBadge`, `DataTable`, `Pagination`, `SearchForm`, `PageHeader`, `SettingsSection`, `Seo`,
`LegalBody`, `LocaleSwitcher`, `AppearanceToggle`, `OrganizationSwitcher`, `UserMenu`,
`ImpersonationBanner`, `Logo`, `TextLink`.

`FormStepper` moves focus to each new step's heading (never on page load), shows a refused
step's `validationMessage` as an alert, can mark the last step as the review
(`reviewLastStep`), offers `skipLabel`/`onSkip` on optional steps, and takes
`stepIndex`/`onStepChange` to be controlled from the page.

Tap targets: every `Button` size is at least 44 px (`h-11`/`size-11`; `lg` is 48 px), and so
are the sidebar trigger and menu buttons. Do not shrink a button with `h-7`-style overrides.
Toasts map every type to theme tokens (Sonner's own rich colours fail contrast). Dates:
`formatDate`/`formatDateTime` read in UTC (server and browser show the same day), put the day
first in English, and the time shows its zone.

Layouts: `PublicLayout` (landing, legal), `AuthLayout` (sign-in style pages), `AppLayout`
(sidebar shell), `SettingsLayout` (inside the app shell), `AdminLayout`. They load lazily.

## UX rules (see AGENTS.md)

Plain words; screens by user task; multi-step forms by default; explain in place; destructive
actions confirm and say the consequence; every empty state offers the first step; mobile first,
44 px targets, visible focus, reduced motion respected.

## Appearance

Light / dark / system per browser (`useAppearance`, `localStorage`), applied before first paint
by an inline script in `frontend/index.html`.

## Re-skin checklist for a product

1. `theme.css`: palette (light + dark), `--typeface-body` / `--typeface-heading`, `--radius`.
2. Fonts: add the `@fontsource-variable/*` package and import it in `app.css`.
3. `components/app/logo.tsx`: the mark; `priv/static/favicon.svg`, then `bin/icons` (favicon.ico,
   apple-touch-icon, manifest icons) and `bin/og-cards.mjs` (social cards per locale, [SEO.md](SEO.md)).
4. `config :starter_kit, :theme_color` and `:mail_brand`.
5. Landing copy lives in `i18n/translations.csv` (`home.*`).

## Frontend

The shared SPA lives in `frontend/src`. TanStack Router waits for bootstrap before applying
route guards; React Query hooks in `api/hooks` own data loading. Forms use react-hook-form
and Zod schemas, preserving guided steps, in-place help and confirmation dialogs. API types
and route helpers in `api/generated` belong to the backend generator once available.

`pnpm build` prerenders the landing in English and Spanish from the same React components
and build-time locale fallback. Runtime catalogue updates come from the locale API. Set
`VITE_PUBLIC_URL` for canonical links and `VITE_API_URL` for a native or separate-origin API.
