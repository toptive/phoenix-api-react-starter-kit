import i18next, { type i18n as I18n } from "i18next"
import { initReactI18next } from "react-i18next"
import en from "../../../i18n/locales/en.json"
import es from "../../../i18n/locales/es.json"
import { storageKey } from "@/lib/storage-keys"

export function createI18n(locale: string, translations: Record<string, string> = {}): I18n {
  const instance = i18next.createInstance()
  void instance.use(initReactI18next).init({
    lng: locale, fallbackLng: "en", resources: { en: { translation: en }, es: { translation: es },
      [locale]: { translation: { ...(locale === "es" ? es : en), ...translations } } },
    keySeparator: false, nsSeparator: false, interpolation: { escapeValue: false }, returnNull: false, initAsync: false,
  })
  return instance
}
export function applyTranslations(instance: I18n, locale: string, translations: Record<string, string>) {
  instance.addResourceBundle(locale, "translation", translations, true, true)
  if (instance.language !== locale) void instance.changeLanguage(locale)
}
const stored = typeof localStorage === "undefined" ? null : localStorage.getItem(storageKey("locale"))
export const i18n = createI18n(stored ?? "en")
i18n.on("languageChanged", (locale) => {
  if (typeof document !== "undefined") document.documentElement.lang = locale
  if (typeof localStorage !== "undefined") localStorage.setItem(storageKey("locale"), locale)
})
