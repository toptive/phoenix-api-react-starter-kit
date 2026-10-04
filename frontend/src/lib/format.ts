/** "Ana María López" → "AL" */
export function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean)
  const first = parts[0]?.[0] ?? "?"
  const last = parts.length > 1 ? (parts[parts.length - 1]?.[0] ?? "") : ""
  return (first + last).toUpperCase()
}

// Day-month-year for English too ("30 Sep 2026", not "Sep 30, 2026").
const dateLocale = (locale: string) => (locale === "en" ? "en-GB" : locale)

/**
 * A date for people, in their language: "30 Sep 2026". Read in UTC, so the server and
 * every browser show the same day (Prerendered markup matches hydration).
 */
export function formatDate(iso: string | null | undefined, locale: string): string {
  if (!iso) return ""
  return new Intl.DateTimeFormat(dateLocale(locale), { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" }).format(new Date(iso))
}

/** A date and time for people, with the zone shown: "30 Sep 2026, 14:05:00 UTC". */
export function formatDateTime(iso: string | null | undefined, locale: string): string {
  if (!iso) return ""
  return new Intl.DateTimeFormat(dateLocale(locale), { dateStyle: "medium", timeStyle: "long", timeZone: "UTC" }).format(new Date(iso))
}

/** Money is stored as integer cents: formatMoney(1250, "EUR", "es") → "12,50 €". */
export function formatMoney(cents: number, currency: string, locale: string): string {
  return new Intl.NumberFormat(locale, { style: "currency", currency }).format(cents / 100)
}
