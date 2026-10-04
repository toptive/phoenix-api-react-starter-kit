# Tenancy

`StarterKit.Organizations` owns organizations, memberships, invitations and onboarding.
`StarterKit.Accounts` owns each device's current organization in its bearer session.

## Model and modes

Organizations carry name (2..80), unique slug, personal and onboarded_at. Memberships and
invitations carry organization_id and are guarded by scoped repository queries. Memberships
have role owner/admin/member and access full/viewer. A manager is an owner or admin with full
access. Invitation tokens are SHA-256 digests, single use, valid for seven days.

`config :starter_kit, :tenancy` is multi by default: a new user gets a personal organization as
owner, joins others through invitations and can create or switch organizations. In single mode,
all users join the default organization; the first is owner, later users are members. Organization
creation returns 403 forbidden in single mode. Bootstrap publishes the mode in app.tenancy.

`%Scope{user, organization, membership, impersonator, session}` travels into tenant context
calls. Each tenant query passes `org_id: Scope.organization_id(scope)`; foreign or missing tenant
record IDs return 404 without revealing another organization's data. Add an isolation case to
`test/starter_kit/tenancy_test.exs` and HTTP isolation coverage for every new tenant schema.

## Endpoints

Bodies are flat camelCase JSON, responses use the API envelope and generated serializer types.
Every private endpoint requires a bearer, with 401 unauthorized for absent/unknown sessions.

| Method | Resource | Access and result |
|---|---|---|
| PUT | `/api/v1/current-organization` | User; organizationId → `Auth` |
| POST | `/api/v1/organizations` | User, multi mode; name → 201 `Organization` |
| GET | `/api/v1/onboarding` | Manager → `Onboarding {organizationName, required}` |
| PUT | `/api/v1/onboarding` | Manager; optional name → `Organization` |
| GET | `/api/v1/invitations/:token` | Public → `InvitationPreview` |
| POST | `/api/v1/invitations/:token/acceptance` | User → 201 `Membership` with user |
| GET | `/api/v1/settings/organization` | Member → `OrganizationSettings {organization, canEdit}` |
| PUT | `/api/v1/settings/organization` | Manager; name → `Organization` |
| GET | `/api/v1/settings/members` | Member → `Membership[]` with users, ordered by insertion |
| PUT | `/api/v1/settings/members/:id` | Manager; role/access → `Membership` with user |
| DELETE | `/api/v1/settings/members/:id` | Manager or that member leaving → empty 204 |
| GET | `/api/v1/settings/invitations` | Manager → pending, unexpired `Invitation[]` |
| POST | `/api/v1/settings/invitations` | Manager; email/role/access → 201 `Invitation` |
| DELETE | `/api/v1/settings/invitations/:id` | Manager → empty 204 |

Policy denials are 403 forbidden. Field validation is 422 validation_failed, with camelCase fields
mapped to `{key, message, bindings?}` lists. Unknown enum values use validation.inclusion.

## Current organization and onboarding

A new session selects the user's last organization, then the first membership, creating the
personal/default organization if needed. Later requests select sessions.organization_id before
that fallback. Switching verifies membership, then updates this device and users.last_organization_id
in one transaction. A foreign organization gives 409 not_member. Other devices keep their selection.
Creating an organization commits the organization, full owner membership, audit and session switch;
it starts onboarded because the name was provided. Analytics: organization_created.

Automatically created organizations begin with onboarded_at null. Managers see
bootstrap.auth.onboardingRequired and can fetch the onboarding questions. Completing onboarding
keeps the existing name when the answer is blank, sets onboarded_at and audits
organization.onboarded. Analytics: onboarding_completed with skipped true when no answer was given.
Members receive 403 on both onboarding endpoints. Organization settings are readable by every
member; canEdit reflects manager permission. Renaming audits organization.updated.

## Membership safety

Role/access changes and removals lock the organization first, then reload the membership and
count owners. Only owners may assign owner or change an owner: violations are field errors on
role using validation.owner_only. Demoting the last owner uses validation.last_owner (422).
Leaving/removing the last owner gives 409 last_owner. An admin cannot remove an owner (403).

Members may delete their own seat. After leaving, the device selects another membership or creates
its personal/default organization, and remembers it on the user. Every successful member change
records membership.updated or membership.deleted. The SPA refetches bootstrap after leaving.

## Invitations

An invitation sends a SPA link `/invitations/:token`. The public preview names the organization
and invited email, role/access, expiresAt and emailMatches (false for anonymous visitors). It never
consumes the token. Unknown, accepted or expired invitations give 422 invitation_invalid.
The SPA retains this path while the visitor signs up or signs in.

Acceptance locks the invitation, verifies the signed-in address case-insensitively, creates a seat
with its role/access or keeps an existing seat, and marks the invitation accepted. It atomically
switches the device and remembers the organization on the user. A wrong address gives 409
email_mismatch with details.email; no membership or acceptance is written. Audit: invitation.accepted;
analytics: invitation_accepted.

Invitation creation refuses with 503 email_unavailable before writes. Owner invitations use
validation.invitation_owner; existing members use validation.already_member; a pending duplicate
uses validation.invitation_pending on email. Expired invitations no longer block that address.
`Billing.invite_member/4` reserves plan capacity under the organization lock, counting members and
pending invitations. A full plan gives validation.limit_reached on email, with limit bindings.
Emails to non-users use the inviter's request locale. Audit: invitation.created/revoked;
analytics: invitation_sent with role. Create is limited to 30/hour and acceptance to 10/minute.

## Email subscriptions

`GET /api/v1/email-subscriptions/:token` publicly returns `EmailSubscription {email, subscribed}`
without changing it. `POST /api/v1/email-subscriptions/:token/opt-out` stops optional email:
JSON callers get the updated subscription; RFC 8058 form posts (`List-Unsubscribe=One-Click`)
get an empty 200 with no cookies or CSRF check. Opt-out is idempotent and audits
user.optional_emails_stopped once, with a 120/minute rate limit.

The signed token names the user and a hash of the address, with no expiry; a changed address or
unknown token gives 404. Optional mail's List-Unsubscribe header targets the API, while its footer
opens `/email-subscriptions/:token/opt-out` in the SPA. List-Unsubscribe-Post declares the one-click
form. Transactional and access emails do not unsubscribe.
