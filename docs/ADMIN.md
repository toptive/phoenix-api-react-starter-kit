# Admin area

`/admin`, superadmins only (`User.role == :superadmin`, not while impersonating). Everyone else
gets a 404. Grant the role in Admin → Users → a user → Role.

## First superadmin

A new installation has no superadmin. Make one with the bootstrap task: it promotes the account
with that email, or creates a confirmed one without a password. The person then signs in with a
magic link (or Google). It is refused once any superadmin exists, so it cannot take over a
running installation (`Accounts.bootstrap_superadmin/1`, audited as `user.superadmin_bootstrapped`).

```sh
mix starter_kit.admin.bootstrap you@example.com                      # dev, staging
kamal app exec 'bin/starter_kit eval "StarterKit.Release.bootstrap_admin(\"you@example.com\")"'   # production
```

| Section | Path | What it does |
|---|---|---|
| Overview | `/admin` | counts and entry points |
| Users | `/admin/users` | search, see organizations, change global role, act as a user (reason required) |
| Organizations | `/admin/organizations` | search, member list |
| Texts | `/admin/translations` | edit every UI text per locale, LLM fill ([I18N.md](I18N.md)) |
| Legal documents | `/admin/legal-documents` | terms, privacy, cookies: versions and publishing |
| Audit log | `/admin/audit-events` | append-only events; search by record id or action |
| Background jobs | `/admin/oban` | Oban Web (open source) |

## Legal documents (`StarterKit.Legal`)

- Three documents: `terms`, `privacy`, `cookies`; each has numbered, immutable versions with a
  title and a body per locale (English required) and an internal note.
- "Save as draft" adds a version; "Publish" makes it the one the public page shows
  (`/legal/:slug`, `/es/legal/:slug`). Old versions stay.
- Bodies are plain text: blank lines separate paragraphs, `## ` starts a heading. They are never
  rendered as HTML.
- `Legal.accept(scope, slug, ip)` records which exact version a user accepted (for products
  that need explicit consent).

## Audit log (`StarterKit.Audit`)

`Audit.record("organization.updated", scope: scope, subject: org, metadata: %{…})` from the
context. The database rejects UPDATE and DELETE on `audit_events` (trigger). Recorded today:
registrations, deletions, role changes, organization and membership changes, invitations,
translation edits, legal versions and publications, impersonation start/stop.
