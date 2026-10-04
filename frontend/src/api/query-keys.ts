export const qk = {
  emailPreferences: ["email-preferences"] as const,
  sessions: ["sessions"] as const,
  accountDeletion: ["account-deletion"] as const,
  invitation: (token: string, user: string) => ["invitation", token, user] as const,
  bootstrap: ["bootstrap"] as const,
  locale: (locale: string, version: string) => ["locale", locale, version] as const,
  magicLink: (token: string) => ["magic-link", token] as const,
  emailConfirmation: (token: string) => ["email-confirmation", token] as const,
  organization: (id: string, resource: string) => ["organization", id, resource] as const,
  legal: (slug: string, locale: string) => ["legal", slug, locale] as const,
}
