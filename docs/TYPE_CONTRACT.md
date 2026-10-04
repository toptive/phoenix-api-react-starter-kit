# Type contract

Serializers and the Phoenix router are the source of TypeScript types and API route helpers.
`mix typelizer.gen` writes `frontend/src/api/generated/{serializers,routes}`;
`mix typelizer.check` rejects drift. Commit the generated output with its source changes.
Never edit generated files or hand-write mirror response interfaces.

## Workflow

1. Change a serializer or API route.
2. Run `mix typelizer.gen` with the dev database running and migrated (column nullability).
3. Update React callers and run `pnpm typecheck`, `pnpm lint`, `pnpm test` and `bin/check`.

The page generator is disabled. API helper names follow Phoenix's singular helper names:
`apiV1AuthSession.create().url`, `apiV1SettingsMembership.delete(id).url`.
The runtime exports `setRoutesBaseUrl`, `setUrlDefaults` and `addUrlDefault`.
API locale path parameters are required; UI locale is sent in Accept-Language.
Browser navigation uses the SPA's paths and TanStack Router, not API helpers.

## Serializers

Schema attributes infer enums and nullability. Computed values declare their types explicitly:

```elixir
attribute :has_password, type: :boolean, value: &(not is_nil(&1.hashed_password))
attribute :sales, type: {:enum, [:open, :test, :closed]}
```

`BillingOverview.sales` is a string enum. `DirectUpload` contains `url`, `key`, `method`
(`"PUT"`) and `headers`; the URL carries its expiry. Dictionary keys retain their spelling.
`ApiErrorBody`, `FieldError` and generic `Envelope` types are also generated from backend
transport declarations. The HTTP client selects metadata using the generated `Pagination`
type. Typelizer's generic `Paginated` uses pageSize; this API uses `meta.pagination.perPage`.

## Helpers consumed outside the SPA

Every generated action must have a caller or an entry here; architecture tests enforce this.
The generator excludes the SPA fallback, `/dev`, `/live` and `/admin/jobs` browser routes.

| Helper | Consumer |
|---|---|
| `health.show` | kamal-proxy container health checks |
| `sitemap.show` | crawlers and public-host reverse proxies |
| `robots.show` | crawlers and public-host reverse proxies |
| `apiV1AuthGoogleCallback.create` | Google OAuth redirect, never called by SPA code |
| `webhooksStripeEvent.create` | Stripe webhook delivery |

Typelizer is a Hex dependency (`~> 0.2`). Propose generator changes upstream, never patch it locally.
