# Architecture

How the rules of `AGENTS.md` are built and enforced.

## 1. Boundaries

Every context is its own [`boundary`](https://hexdocs.pm/boundary). A forbidden reference is
a compiler warning, and `mix compile --warnings-as-errors` fails every gate.

| Boundary | Depends on | Exports |
|---|---|---|
| `StarterKitWeb` | contexts, platform modules, `Policy`, `Health` | `Endpoint`, `Telemetry`, `Vite`, `RateLimit` |
| `StarterKit.Accounts` | `Repo`, `Schema`, `Policy`, `Audit`, `Notifications` | `User`, `UserToken`, `Scope`, `UserPolicy`, `Impersonation` |
| `StarterKit.Organizations` | the above + `Accounts` | `Organization`, `Membership`, `Invitation`, their policies |
| `StarterKit.I18n` | `Repo`, `Schema`, `Policy`, `Audit`, `AI` | `Translation`, `TranslationPolicy` |
| `StarterKit.Legal` | `Repo`, `Schema`, `Policy`, `Audit` | `LegalDocument`, `LegalDocumentVersion`, `LegalDocumentPolicy` |
| `StarterKit.Audit` | `Repo`, `Schema`, `Policy` | `AuditEvent`, `AuditEventPolicy` |
| platform: `Notifications`, `Mailer`, `AI`, `Analytics`, `Uploads`, `Monitoring`, `Health` | what they call | nothing but the module |
| `StarterKit.Repo`, `Schema`, `Policy` | — | the module |

A context exports its API module, its **schemas** (data types that web code pattern-matches and
serializes) and its **policies**. Helper modules (`I18n.Catalog`, `Uploads.UploadGuard`,
`Notifications.Email`, workers) are private. The web layer does not depend on `Repo`.

Check it: `mix boundary.spec` prints the graph.

## 2. Controllers

- REST actions only (`index show new create edit update delete`); enforced by
  `credo/rest_actions.ex`. Other verbs become nested resources:
  `POST /invitations/:token/acceptance`, `PUT /current-organization`,
  `POST /admin/legal-documents/:slug/versions/:number/publication`.
- Shape of an action:

  ```elixir
  def show(conn, _params) do
    conn = authorize!(conn, :show, scope(conn).user)
    render_data(conn, {Serializers.UserSerializer, scope(conn).user})
  end
  ```

- Converted controllers live in `controllers/api/v1`; they do not declare Inertia pages.
  Unconverted areas retain their existing controllers and rendering until conversion.
- `StarterKitWeb.ErrorPages` wraps actions: policy denial → 403 `forbidden`, missing record →
  404 `not_found`, both in the API envelope. Unconverted browser pages keep `errors/show`.
- OAuth's imposed GET callback is modelled as `create` on its own resource controller.
  Magic links and email confirmation tokens are spent only by POST.

## 3. Authorization (the Pundit equivalent)

```elixir
defmodule StarterKit.Organizations.MembershipPolicy do
  @behaviour StarterKit.Policy
  @impl true
  def authorize(%Scope{} = scope, :index, Membership), do: not is_nil(scope.membership)
  def authorize(_scope, _action, _resource), do: false   # deny by default
end
```

- The schema names its policy: `use StarterKit.Schema, policy: …`.
- `authorize!(conn, action, struct_or_schema_module)` resolves the policy, raises
  `NotAuthorizedError` (403) or marks the conn authorized. `can?/3` feeds UI permissions
  (`canManage` props).
- `Plugs.VerifyAuthorized` (every authenticated pipeline) fails any action that neither
  authorized nor called `skip_authorization/1`; `test/architecture/rules_test.exs` finds the
  same mistake statically.

## 4. Tenant guard

`StarterKit.Repo.prepare_query/3`: a query whose root schema is declared `tenant: true` must
pass `org_id:` (adds `WHERE organization_id = ?`) or `skip_org_id: true` (a deliberate
cross-tenant read: "my memberships", admin lists). Otherwise it raises `Repo.TenantError`.
Inserts and updates of structs are not queries: the context sets `organization_id` from the scope.
`test/starter_kit/tenancy_test.exs` has one isolation case per tenant schema (enforced).

## 5. Contexts

Business rules, validation, transactions (`Repo.transact/1` + `with`), notifications,
auditing and job enqueueing live in the context. Contexts return `{:ok, _}` /
`{:error, changeset | atom}`; the web layer turns them into flashes, Inertia errors or the JSON
error envelope.

## 6. Jobs

Oban with queues `default` and `marketing`, `Pruner` (7 days), `Lifeline`, `Cron`. A worker
lives inside its context and its `perform/1` is ONE call (`credo/worker_perform.ex`):

```elixir
def perform(%Oban.Job{args: args}), do: Notifications.deliver_now(args)
```

Concurrency stays below the DB pool (`POOL_SIZE` 8, jobs 5 + 2). Oban Web at `/admin/oban`.

## 7. Responses and the wire

- `/api/v1`: `Responses.render_data/3` takes serialized data or `{serializer, value}` plus
  a metadata map, always returning `{data, meta}`. Set status on the conn before rendering.
  `render_collection/4` serializes a list and includes pagination metadata.
- `render_error/4` returns `{error: {code, message, details}}`. Codes are stable English;
  messages use the request locale. `render_validation_error/2` returns 422 `validation_failed`
  with field → `{key, message, bindings?}` lists. Details and identifier keys are camelCase; dotted
  translation keys and locale identifiers retain their spelling.
- Only `render_data`, `render_collection` and `render_error` may call `json/2`; architecture
  tests enforce this. `ErrorJSON` reuses the envelope builder for unmatched routes and errors.
  `ErrorResponses` marks API requests as JSON and all errors as private, no-store and noindex.

## 8. API request pipeline

The endpoint assigns a request id and resolves client IP before JSON parsing. Only configured
proxy hops may supply forwarding headers. API CORS uses `cors_origins` (`CORS_ORIGINS`, default
`SPA_ORIGIN`), including OPTIONS preflights; no credential cookies are enabled.

The `:api` pipeline accepts JSON, fetches query parameters, converts incoming keys with
`SnakeCaseParams`, loads `BearerAuth`, negotiates `ApiLocale`, and installs `VerifyAuthorized`.
There is no session fetch or CSRF check. Locale order: `?locale=` → quality-ranked
`Accept-Language` → authenticated user's preference → CSV default. Cookies are not consulted.

`require_authenticated_api_user` returns 401; `BearerAuth.require_sudo` returns 403
`sudo_required`; `BearerAuth.require_superadmin` returns 404 for anonymous, ordinary or
impersonating callers. Contexts receive the resolved `%Scope{}` for tenant queries.

`GET /api/v1/bootstrap` is public and returns nullable `auth` (user, organization, membership,
organizations, impersonator, superadmin, onboardingRequired, sudoUntil, sessionId),
locale/locales/i18nVersion, public flags, app and Turnstile configuration. Personalized bootstrap responses are private, no-store.
`GET /api/v1/locales/:locale` returns a flat map in `data`; its ETag combines locale and i18n
version, and matching `If-None-Match` returns 304. Unknown locales return 404.

Serializers and router helpers generate to `frontend/src/api/generated/{serializers,routes}`.
The pages generator is disabled. Existing `assets/js/generated` files remain as the unconverted
frontend's snapshot; new API controllers never use `Typelizer.InertiaPage`.

## 9. Browser pipeline during conversion

Unconverted areas retain `SnakeCaseParams → secure headers + CSP nonce → cookie scope →
locale → Inertia → ValidateProps → shared props`. Signed-in and superadmin checks stay in place.
Their sign-in redirects point to the SPA. Browser sessions use the shared digested `sessions` table; their cookie transport is a temporary compatibility layer;
the new API never accepts them. Remaining browser controllers retain Inertia rendering,
`page/2` runtime prop validation and form redirects until their conversion.
