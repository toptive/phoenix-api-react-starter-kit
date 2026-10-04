# SEO

## Server-side rendering

Public pages call `render_public/3`: `indexable` (no `noindex` meta) and SSR when
`config :starter_kit, :ssr` is true (production). Inertia sends the page to a Node worker
(`Inertia.SSR`, one worker by default) that runs `priv/ssr/ssr.js`; crawlers get complete HTML
and the browser hydrates it. Pages behind sign-in render in the browser and are `noindex`.

- **Hydration**: `app.tsx` hydrates when `#app` already has children (SSR) and renders from
  scratch when it is empty (CSR). Inertia sets no marker attribute, so never test for one.
- **The raw `<title>`**: Inertia moves the SSR `<title>` into the `page_title` assign, already
  HTML-escaped by React. `Layouts.page_title/1` unescapes it before HEEx escapes it once
  ("Terms &amp; privacy", never "&amp;amp;"); without SSR it is the app name.
- `test/starter_kit_web/ssr_head_test.exs` builds the real SSR bundle and checks the raw head
  of public pages per locale (one title, the page's own, escaped once; React markup in `#app`).

Dev: `SSR=1 mix phx.server` rebuilds the SSR bundle on change and renders public pages on the server.

## Cookie-free, cacheable public pages

Public routes pipe through `[:public, :browser]`. `Plugs.PublicPage` treats a request with no
`Cookie` and no `Authorization` header as anonymous:

- **No cookie.** The response drops the session cookie and Inertia's `XSRF-TOKEN`, and the root
  layout leaves out the `csrf-token` meta. A visitor from search or an ad gets no cookie until
  they open a form page (sign-in, sign-up): those keep the session and the CSRF token as usual.
- **One URL, one page.** Nobody is signed in, the flash is empty and the locale comes from the
  path only (`Plugs.Locale` skips `?locale=`, the session and `Accept-Language`).
- **Validators before SSR.** `render_public/3` sets a weak `ETag` (page and shared props, asset
  version, date), `cache-control: public, max-age=0, must-revalidate` and
  `vary: X-Inertia, Cookie`. A matching `If-None-Match` gets `304` with no render.

A request with a cookie (a signed-in user, or anyone who opened a form page) runs the normal
browser chain and gets `private, no-store`, so personal pages never reach a shared cache. Inertia
visits (`X-Inertia`) are `private, no-store` too. The CSP nonce is per response; if a product
lets a CDN keep the HTML (`s-maxage`), the cached nonce is shared by every visitor of that copy.
A public page must therefore never render user input.

## Per-page tags

`StarterKitWeb.SEO.build(conn, path:, title:, description:, image:, json_ld:)` → `seo` prop →
`<Seo>` renders title, description, canonical, `hreflang` alternates (+ `x-default`), Open Graph,
Twitter card and JSON-LD blocks inside Inertia's `<Head>`. Helpers: `SEO.organization_json_ld/0`,
`SEO.website_json_ld/1`, `SEO.breadcrumb_json_ld(conn, [{name, path}])` (home first, unlocalized
paths; legal pages use it). `jsonLdText` in `seo.tsx` writes `<` as `\u003c`, so no value can
close the script tag (`ssr_head_test.exs` checks the real SSR HTML). Default share image: one card per locale,
`priv/static/images/og-<locale>.png` (1200×630, < 150 KB), picked by `SEO.default_image/1`.

## Social cards and icons

- `bin/og-cards.mjs` renders the cards from the product itself: `theme.css` colours and font,
  `favicon.svg`, and the `app.name` + `og.tagline` keys of each locale. Run it after a rename,
  a re-skin or a copy change: `PLAYWRIGHT_MODULE=…/node_modules/playwright bin/og-cards.mjs`
  (needs any Playwright install and ImageMagick).
- `bin/icons` builds `favicon.ico`, `apple-touch-icon.png` and `icon-192/512.png` (listed in
  `site.webmanifest`) from `favicon.svg` (needs `rsvg-convert` and ImageMagick).
- Error responses (status ≥ 400, the last-resort pages too) carry `x-robots-tag: noindex` and
  `cache-control: private, no-store` (`Plugs.ErrorResponses`).

## Launch safety

`test/starter_kit_web/placeholder_test.exs` fails while a product still ships a template
placeholder: the template name, a `CHANGE_ME`/`example.com` host or sender in `config/deploy.yml`,
the template favicon, icons or social cards (by fingerprint), or Phoenix default copy. In the
template itself (the `.template-repo` marker, deleted by `bin/rename`) these checks are skipped;
a template-only test keeps the recorded fingerprints current. After you change a template brand
file, update its fingerprint in the test.

## Localized URLs

Default locale at `/…`, others at `/:locale/…` (one router scope, last in the router).
`Plugs.PathLocale` answers 404 for an unknown locale and 301-redirects the default locale
(`/en/legal/terms` → `/legal/terms`), so every page has one canonical URL. On the server,
`SEO.localized_path/2` maps a path to a locale; in React, `usePublicRoutes()` picks the
unprefixed or the `localized*` route helper, and the `:locale` param comes from typelizer URL
defaults (`setUrlDefaults` in `app.tsx` and `ssr.tsx`).

## sitemap.xml and robots.txt

`/sitemap.xml` lists every public page in every locale with `xhtml:link` alternates (home + the
published legal pages; add product pages in `SitemapController`). `/robots.txt` allows public
pages, disallows the app, admin and API, and points to the sitemap.

robots.txt has one group for `*` and one per search or AI-answer crawler (`Googlebot`, `Bingbot`,
`OAI-SearchBot`, `ChatGPT-User`, `Claude-SearchBot`, `Claude-User`, `PerplexityBot`,
`Perplexity-User`): a bot obeys only its own group, so each one repeats the private paths.
AI-training crawlers (`GPTBot`, `ClaudeBot`, `Google-Extended`, `CCBot`) are allowed only when
listed in `config :starter_kit, :allowed_training_bots` (all of them by default); remove one to
send it `Disallow: /`. Add a private path to `@private` in `RobotsController`.

## Canonical host

`Plugs.CanonicalHost` (in the endpoint) sends every request on another host (`www.`, the server
IP, an old domain) to `PHX_HOST` with the same path and query: 301 for GET and HEAD, 308 for
other methods. `/health` is never redirected (kamal-proxy checks it on the container address).
It is on only when `config :starter_kit, :canonical_host` is set (production `runtime.exs`).
kamal-proxy routes only the hosts in `proxy.host`/`proxy.hosts`: to redirect `www.`, add it there.

## Indexing lock

`SITE_INDEXING` (the `:site_indexing` flag, `StarterKit.Flags`) is `0` by default in production and `1`
elsewhere. While it is `0`, `Plugs.SiteIndexing` (in the endpoint) adds
`x-robots-tag: noindex, nofollow` to every response, static files and errors too; the root layout
adds `<meta name="robots" content="noindex">` to every page; robots.txt is
`Disallow: /` and the sitemap is empty. Set `SITE_INDEXING: "1"` in `config/deploy.yml` on launch
day. A staging or preview deploy keeps it at `0`.

## Performance

Lighthouse on the landing (production image): see [PERFORMANCE.md](PERFORMANCE.md).
