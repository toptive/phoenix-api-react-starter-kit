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
  def update(conn, %{"organization" => params}) do
    organization = scope(conn).organization
    conn = authorize!(conn, :update, organization)

    case Organizations.update_organization(scope(conn), organization, params) do
      {:ok, _} -> conn |> put_flash_t(:info, "flash.organization.updated") |> redirect(to: ~p"/settings/organization/edit")
      {:error, changeset} -> conn |> assign_changeset_errors(changeset) |> redirect(to: ~p"/settings/organization/edit")
    end
  end
  ```

- `StarterKitWeb.ErrorPages` wraps every action: a denied policy renders the Inertia page
  `errors/show` with 403, a missing record with 404 (the JSON envelope under `/api`).
- The only exception to "GET has no side effects" is the email-change confirmation link and the
  OAuth callback, both imposed by email/OAuth; both are documented in their controllers.

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

- Inertia pages: `render_inertia/3` (app) or `render_public/3` (SSR + `indexable`).
- Props and JSON keys are camelCase (`camelize_props: true` + serializers). Incoming params are
  converted to snake_case (`Plugs.SnakeCaseParams`); form errors come back camelized, matching
  the camelCase form fields. Data maps whose keys must survive (the i18n catalogue) use
  `preserve_case/1`.
- `/api/v1`: `render_data/3` → `{data, meta}`, `render_error/4` → `{error: {code, message, details}}`.
  Raw `json/2` exists only in `StarterKitWeb.Responses` (architecture test).

## 8. Request pipeline (browser)

`SnakeCaseParams → secure headers + CSP nonce → current scope (user, organization,
impersonator) → locale → Inertia → typelizer ValidateProps (dev/test) → shared props`.
Authenticated scopes add `require_authenticated_user` + `VerifyAuthorized`; the admin scope adds
`require_superadmin` (404 for everyone else).
