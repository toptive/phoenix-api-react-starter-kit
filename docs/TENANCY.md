# Tenancy

Context: `StarterKit.Organizations`.

## Model

- `Organization` — the tenant (`name`, `slug`, `personal`).
- `Membership` — a user's seat: `role` (`owner | admin | member`) and `access` (`full | viewer`).
  Owners and admins with full access manage the organization and its people; `viewer` reads only.
  Only owners create owners; the last owner cannot leave or be demoted. Membership changes and
  account deletion lock the organization row (`Organizations.lock_organizations/1`, `FOR UPDATE`
  in id order) before they count owners, so two owners cannot remove each other at once.
- `Invitation` — email, role, access, SHA-256 of a single-use token, 7-day expiry. Owners cannot
  be invited directly (promote after they join).
- `%Scope{user, organization, membership, impersonator}` travels into every context call.

## Modes (`config :starter_kit, :tenancy`)

| Mode | Behaviour |
|---|---|
| `:multi` (default) | A new user gets a personal organization as owner. People join others by invitation and switch in the sidebar. |
| `:single` | One organization (`default` slug). The first user is its owner, everyone else joins as member. The switcher and "Create an organization" are hidden. |

The data model is the same in both modes, so a product can move from single to multi later.

## Current organization

`UserAuth.fetch_current_scope_for_user/2` builds the scope from the session's `organization_id`,
else the user's last organization, else the first membership (creating the personal or default
organization when the user has none). Switching = `PUT /current-organization`.

## Onboarding

`organizations.onboarded_at` is nil until a manager (owner or admin with full access) finishes
`/onboarding/edit`. The dashboard sends such a manager there; members and an impersonating admin
never see it. Organizations created automatically (personal, or the single-mode default) start
there; one made with "Create an organization" already gave its name and starts onboarded.

The starter asks one optional question (the organization's name) in a `FormStepper` with
"Skip for now" and a review step; a blank answer keeps the current name. A product replaces the
steps in `pages/onboarding/edit.tsx` and what `Organizations.complete_onboarding/2` saves.

## Tenant guard and isolation tests

See [ARCHITECTURE.md §4](ARCHITECTURE.md). A new tenant schema:

1. `use StarterKit.Schema, policy: MyPolicy, tenant: true` and an `organization_id` column.
2. Context functions take the scope and query with `org_id: Scope.organization_id(scope)`.
3. Add its case to `test/starter_kit/tenancy_test.exs` (the architecture test requires it).

## Invitations flow

Settings → People → "Invite someone" (three steps: email, what they can do, review). The email
links to `/invitations/:token`: signed in with the invited email → "Accept"; signed out → sign up
or sign in, then back to the invitation (the link is kept in the session).
