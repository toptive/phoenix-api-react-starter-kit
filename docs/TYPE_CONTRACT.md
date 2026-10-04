# Type contract (typelizer)

The Elixir side declares the shape of every value sent to React. [typelizer](https://github.com/toptive/typelizer-ex)
generates the TypeScript from it, so types cannot drift.

| Source | Generates | Import |
|---|---|---|
| `lib/starter_kit_web/serializers/*.ex` | `frontend/src/api/generated/serializers/*.ts` | `import type { User } from "@/api/generated/serializers"` |
| `StarterKitWeb.Router` | `frontend/src/api/generated/routes/*.ts` | `routes.apiV1AuthSession.create().url` |

The pages generator is disabled. Existing Inertia declarations and runtime validation remain
for unconverted areas; their old `assets/js/generated` output is a compatibility snapshot.
New API controllers use serializers only. The flat catalogue response type is the generated
`Locale["translations"]`; bootstrap and auth session data use `Bootstrap` and `AuthSession`.

## Workflow

1. Change a serializer, a route, or a page's props.
2. `mix typelizer.gen` (the Claude hook runs it after such edits).
3. Use the new types; commit the generated files with the change.

`mix typelizer.check` fails when the committed files differ (pre-commit, pre-push, `/deploy`).
It reads column nullability from the dev database (`config :typelizer, repo:`), so the dev DB
must be up and migrated.

In dev and test (`validate_inertia_props: :values`), `Typelizer.InertiaPage.ValidateProps` raises
when a rendered page sends a prop that is not declared, misses one, or sends a value that does
not match its declared type (enums, nullability, serializer fields, nested lists — reported with
a path such as `memberships[2].role`). Every page has a controller test, so a mismatch fails `mix test`.

## Serializers

```elixir
defmodule StarterKitWeb.Serializers.MembershipSerializer do
  use Typelizer.Serializer, schema: StarterKit.Organizations.Membership

  attributes [:id, :role, :access, :inserted_at]
  has_one :user, serializer: StarterKitWeb.Serializers.UserSerializer, nullable: true
end
```

- Computed values: `attribute :has_password, type: :boolean, value: &(not is_nil(&1.hashed_password))`.
- A serializer without `schema:` declares a `type:` for each attribute.
- `Ecto.Enum` fields become literal unions (`"owner" | "admin" | "member"`).
- Never write a TypeScript interface that mirrors server data by hand.

## Routes

Groups follow the Phoenix helper name: `routes.adminUser.show(id).url`,
`routes.invitationInvitationAcceptance.create(token).url`, `routes.adminUser.index({ query: compact({ q }) }).url`.
Excluded: `/dev`, `/live`, Oban Web assets. Never type a path in React.

URL defaults (`config :typelizer, routes: [defaults: [:locale]]`): `:locale` is optional in the
helper types and filled from the current language (`setUrlDefaults(() => ({ locale: i18n.language }))`
in `app.tsx`, set per render in `ssr.tsx`): `routes.localizedLegalPage.show("terms").url` →
`/es/legal/terms`. Add organization-scoped defaults the same way (`addUrlDefault`).

Also available since 0.2 and not used by the template yet: typed query params
(`use Typelizer.Query`) and `Typelizer.Envelope` (`{:paginated, item}` → `Paginated<T>`).

## Dependency

`{:typelizer, "~> 0.2"}` from Hex ([docs](https://hexdocs.pm/typelizer)). Library changes are
proposed to the typelizer maintainers, never patched locally.
