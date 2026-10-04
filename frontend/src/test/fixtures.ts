import type { Auth, AuthSession, Bootstrap, User } from "@/api/generated/serializers"
export const user: User = {
  id: "user-1",
  name: "Ana",
  email: "ana@example.com",
  role: "user",
  locale: "en",
  confirmedAt: "2026-01-01T00:00:00Z",
  insertedAt: "2026-01-01T00:00:00Z",
  hasPassword: true,
}
export const auth: Auth = {
  user,
  organization: { id: "org-1", name: "Ana's workspace", slug: "ana", personal: true },
  membership: { id: "membership-1", role: "owner", access: "full", insertedAt: "2026-01-01T00:00:00Z", user: null },
  organizations: [],
  superadmin: false,
  impersonator: null,
  onboardingRequired: false,
  sudoUntil: "2099-01-01T00:00:00Z",
  sessionId: "session-1",
}
export const bootstrap: Bootstrap = {
  auth: null,
  locale: "en",
  locales: ["en", "es"],
  i18nVersion: "test",
  app: {
    name: "StarterKit",
    tenancy: "multi",
    signupMode: "open",
    emailAvailable: true,
    googleEnabled: true,
    jobsDashboard: false,
    publicUrl: "https://starter.example",
  },
  flags: { billing: false },
  turnstile: { required: false, siteKey: null },
}
export const session: AuthSession = {
  token: "new-bearer",
  expiresAt: "2099-01-01T00:00:00Z",
  sudoUntil: "2099-01-01T00:00:00Z",
  user,
  impersonator: null,
  newAccount: false,
}
