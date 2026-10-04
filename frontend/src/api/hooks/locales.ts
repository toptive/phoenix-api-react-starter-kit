import { queryOptions, useQuery } from "@tanstack/react-query"
import { api } from "../http"
import { apiV1Locales } from "../generated/routes"
import { qk } from "../query-keys"
import { applyTranslations, i18n } from "@/i18n"
import { storageKey } from "@/lib/storage-keys"

type Catalogue = { translations: Record<string, string>; etag: string }
function readCatalogue(locale: string): Catalogue | null {
  try {
    return JSON.parse(localStorage.getItem(storageKey(`catalogue:${locale}`)) ?? "null")
  } catch {
    return null
  }
}
export function restoreLocale(locale: string) {
  const stored = readCatalogue(locale)
  applyTranslations(i18n, locale, stored?.translations ?? {})
}
export const localeOptions = (locale: string, version: string) =>
  queryOptions({
    queryKey: qk.locale(locale, version),
    queryFn: async ({ signal }) => {
      const previous = readCatalogue(locale)
      const result = await api.get<Record<string, string>>(apiV1Locales.show(locale), {
        signal,
        ...(previous ? { headers: { "If-None-Match": previous.etag } } : {}),
      })
      const translations = result.data ?? previous?.translations ?? {}
      const currentVersion = typeof result.meta?.version === "string" ? result.meta.version : version
      localStorage.setItem(
        storageKey(`catalogue:${locale}`),
        JSON.stringify({ translations, etag: `"${locale}:${currentVersion}"` }),
      )
      applyTranslations(i18n, locale, translations)
      return translations
    },
    staleTime: Infinity,
    retry: false,
  })
export const useLocales = (locale: string, version: string) => useQuery(localeOptions(locale, version))
