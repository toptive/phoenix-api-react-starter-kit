# Privacy and account deletion

`StarterKit.Privacy` owns account deletion. Both endpoints require a signed-in bearer and an
open ten-minute sudo window; missing or expired sudo gives 403 `sudo_required`.

`GET /api/v1/settings/account` returns `AccountDeletion {blocker}`. The blocker is null or an
object with `reason` and the organization's name. A last owner with other members must first
make another member an owner (`transfer_ownership`). The only member of an organization must
cancel any subscription that can still charge (`subscription_active`): every status except
`canceled` and `incomplete_expired`, in either billing mode, even while billing is disabled.

`DELETE /api/v1/settings/account` locks the user's organizations in id order, reloads memberships
and re-checks these blockers in the same transaction. A blocker returns 409 with its stable
code and `details: {organization: "<name>"}`; the user, memberships, tokens and audit log are
unchanged. A clear preview is not a promise that a later deletion will be allowed.

Successful deletion returns an empty 204. Foreign-key cascades remove memberships, bearer
sessions and emailed tokens. Legal acceptances survive with `user_id = null` and their email
hash as proof of consent. An organization left empty is deleted with its tenant data unless it
has billing history; that organization and its billing history remain. Shared organizations
remain for their other members. The transaction records `user.deleted` and, for removed empty
organizations, `organization.deleted` in the append-only audit log.

The SPA clears its bearer after success. The endpoint is limited to five requests per minute
per resolved client IP. Over-limit responses use 429 `rate_limited`, `Retry-After`, and
`details.retryAfter`. Account deletion does not run seeds or contact a payment provider.
