import i18next, { type i18n as I18n } from "i18next"
import { initReactI18next } from "react-i18next"
const catalogues = import.meta.glob<Record<string, string>>("../../../i18n/locales/*.json", {
  eager: true,
  import: "default",
})
const bundled = Object.fromEntries(
  Object.entries(catalogues).map(([path, translation]) => [
    path
      .split("/")
      .at(-1)!
      .replace(/\.json$/, ""),
    { translation },
  ]),
)
export const bundledLocales = Object.keys(bundled)
import { storageKey } from "@/lib/storage-keys"

export function createI18n(locale: string, translations: Record<string, string> = {}): I18n {
  const instance = i18next.createInstance()
  void instance.use(initReactI18next).init({
    lng: locale,
    fallbackLng: "en",
    resources: {
      ...bundled,
      [locale]: { translation: { ...(bundled[locale]?.translation ?? bundled.en?.translation), ...translations } },
    },
    keySeparator: false,
    nsSeparator: false,
    interpolation: { escapeValue: false },
    returnNull: false,
    initAsync: false,
  })
  return instance
}
export function applyTranslations(instance: I18n, locale: string, translations: Record<string, string>) {
  instance.addResourceBundle(locale, "translation", translations, true, true)
  if (instance.language !== locale) void instance.changeLanguage(locale)
}
const stored = typeof localStorage === "undefined" ? null : localStorage.getItem(storageKey("locale"))
export const i18n = createI18n(stored ?? "en")
if (typeof document !== "undefined") document.documentElement.lang = i18n.language
i18n.on("languageChanged", (locale) => {
  if (typeof document !== "undefined") document.documentElement.lang = locale
  if (typeof localStorage !== "undefined") localStorage.setItem(storageKey("locale"), locale)
})
