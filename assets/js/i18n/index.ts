import i18next, { type i18n as I18n } from "i18next"
import { initReactI18next } from "react-i18next"

/**
 * i18next with a flat catalogue (keys like "auth.session.title"). The server sends the
 * catalogue as the `translations` prop on the first page load and whenever the locale or
 * the catalogue version changes (see StarterKitWeb.Plugs.InertiaShare).
 */
export function createI18n(locale: string, translations: Record<string, string>): I18n {
  const instance = i18next.createInstance()
  void instance.use(initReactI18next).init({
    lng: locale,
    fallbackLng: false,
    resources: { [locale]: { translation: translations } },
    keySeparator: false,
    nsSeparator: false,
    interpolation: { escapeValue: false },
    returnNull: false,
    initAsync: false,
  })
  return instance
}

/** Adds or replaces the catalogue of `locale` and switches to it. */
export function applyTranslations(instance: I18n, locale: string, translations: Record<string, string>) {
  instance.addResourceBundle(locale, "translation", translations, true, true)
  if (instance.language !== locale) void instance.changeLanguage(locale)
}
