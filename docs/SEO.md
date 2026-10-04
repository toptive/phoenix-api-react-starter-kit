# SEO and public infrastructure

The React SPA owns the head for home and published legal pages: title, description,
canonical, hreflang, Open Graph and JSON-LD. Prerendering is a frontend build concern.
The API serves `/health`, `/sitemap.xml` and `/robots.txt` directly, without JSON envelopes,
authentication or cookies. Canonical-host enforcement and the indexing lock remain in the endpoint.

## Public origin and locales

`PUBLIC_URL` is the public SPA origin, defaulting to `SPA_ORIGIN`. Sitemap locations,
alternates and the robots sitemap link use it rather than the API endpoint origin. `SEO.url/1`
and `SEO.localized_path/2` centralize these mappings. English (the default locale) has no prefix:
`/`, `/legal/terms`. Spanish uses `/es`, `/es/legal/terms`. Legal API content comes from
`GET /api/v1/legal-pages/:slug` with the request locale and English fallback per field;
the SPA renders plain text safely and constructs its head from this content.

## Sitemap

`GET /sitemap.xml` returns `application/xml`, listing home plus published legal slugs
(`terms`, `privacy`, `cookies`) in every supported CSV locale. Each location includes
`xhtml:link` alternates for every locale. Draft and unpublished documents are excluded.
The public base URL is XML-escaped. A product adding public pages extends the sitemap path
list. When origins differ, the SPA web server proxies `/sitemap.xml` and `/robots.txt` to
the API so crawler discovery still works on the public host.

## Robots

`GET /robots.txt` returns `text/plain`. One group for `*` and each search/AI-answer bot
(`Googlebot`, `Bingbot`, `OAI-SearchBot`, `ChatGPT-User`, `Claude-SearchBot`, `Claude-User`,
`PerplexityBot`, `Perplexity-User`) allows public pages and repeats all private paths:

```text
/admin /api /dashboard /onboarding /settings /session /registration /magic-links
/invitations /auth /email-subscriptions /sudo/new /session/check-your-email
/errors/403 /errors/404 /errors/500
```

AI-training bots (`GPTBot`, `ClaudeBot`, `Google-Extended`, `CCBot`) get individual groups;
only bots listed in `allowed_training_bots` are allowed (all four by default). Removed bots
get `Disallow: /`. Both open and locked robots responses end with
`Sitemap: <PUBLIC_URL>/sitemap.xml`.

## Indexing lock

`SITE_INDEXING` controls the private `site_indexing` flag: off in production until launch,
on elsewhere. While off, `Plugs.SiteIndexing` adds `X-Robots-Tag: noindex, nofollow` to every
response, including static files and errors; robots disallows everything and sitemap has
an empty `urlset`. The SPA's head must also respect its deployment's indexing policy.
In `config/deploy.yml`, set `site_indexing = "1"` on launch: it writes both
`SITE_INDEXING` and the build arg `VITE_SITE_INDEXING`. Previews and staging keep it off. Error responses are always
noindex and uncacheable (`Plugs.ErrorResponses`).

## Canonical API host and health

`Plugs.CanonicalHost` redirects other hosts to the configured API endpoint host, retaining
the path and query: 301 for GET/HEAD, 308 for writes. It is configured by `PHX_HOST` in
production. `/health` bypasses this rule so the deployment proxy can probe the container.
Health returns text `ok` (200) or `database unavailable` (503), always `Cache-Control: no-store`.
The DB check is `SELECT 1` with a two-second timeout.

## Branding and launch checks

`bin/og-cards.mjs` creates per-locale cards from theme colours, fonts, logo and CSV copy;
`bin/icons` generates application icons from the favicon. Placeholder checks under
`test/starter_kit_web/placeholder_test.exs` are skipped for `.template-repo`, then enforce
product branding after `bin/rename`. Landing performance targets and tuning are described
in [PERFORMANCE.md](PERFORMANCE.md).

## Static public pages

`pnpm build` prerenders landing pages for every bundled locale. Set `VITE_PUBLIC_URL` and
`VITE_SITE_INDEXING` for the deployment. Optional `VITE_PRERENDER_API_URL` fetches published
legal documents during the build; omit it when an API is not yet available. Phoenix serves
these public paths' own `index.html` files, with the root SPA index as fallback. Browser 404s
belong to TanStack Router. Hashed assets cache for a year; HTML is private, no-store because
the inline appearance bootstrap receives a per-request CSP nonce. No Node process runs in
production. JSON-LD and legal seed scripts are data; only the bootstrap gets an execution nonce.
