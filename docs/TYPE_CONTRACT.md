# Type contract

Serializers and the Phoenix router are the source of TypeScript types and API route helpers.
`mix typelizer.gen` writes `frontend/src/api/generated/{serializers,routes}`;
`mix typelizer.check` rejects drift. Commit the generated output with its source changes.
Never edit generated files or hand-write mirror response interfaces.

## Workflow

1. Change a serializer or API route.
2. Run `mix typelizer.gen` with the dev database running and migrated (column nullability).
3. Update React callers and run `pnpm typecheck`, `pnpm lint`, `pnpm test` and `bin/check`.

The page generator is disabled. `routes: [naming: :controller_path]` uses the shared contract:
plural URL resource names (`apiV1AuthMagicLinks`, `apiV1SettingsSessions`), nested resources
concatenated (`apiV1AdminLegalDocumentsVersionsPublication`), and `destroy` for DELETE.
Explicit `group_overrides` keep session singleton URLs in their plural contract groups.
Helpers accept positional path parameters in URL order, then optional `{ query }` options.
Files live under `routes/Api/V1/<Namespace>/<Controller>Controller.ts`, have default exports,
and are re-exported by `index.ts`. The runtime exports `setBaseUrl` and `RouteDefinition`.

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
| `webhooksStripeEvents.create` | Stripe webhook delivery |

## Switching typelizer to Hex

Typelizer is vendored at `vendor/typelizer` from the `route-naming-controller-path` branch,
commit `38c0918`. This snapshot makes builds and new products independent of sibling checkouts.
Generator changes belong in the library. Keep its MIT license with the snapshot.

Once controller-path naming and `group_overrides` are released on Hex, make these changes together:

1. Replace the path dependency in `mix.exs` with `{:typelizer, "~> 0.3"}`, run `mix deps.get`
   and commit the updated `mix.lock`.
2. Delete `vendor/typelizer/`.
3. Remove `COPY vendor/typelizer vendor/typelizer` and the complete sibling-path guard
   (`RUN if ... fi`) from `Dockerfile`.
4. Remove the `vendor/` exclusion from `bin/rename`.
5. Run `mix typelizer.gen`, review any generated changes, and run `bin/check` before committing.
