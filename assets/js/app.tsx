import "../css/app.css"

import { createInertiaApp, router } from "@inertiajs/react"
import { StrictMode } from "react"
import { createRoot, hydrateRoot } from "react-dom/client"
import { I18nextProvider } from "react-i18next"

import { AppProviders } from "@/components/app/app-providers"
import type { SharedProps } from "@/generated/pages"
import { setUrlDefaults } from "@/generated/routes"
import { applyAppearance, readAppearance } from "@/hooks/use-appearance"
import { applyTranslations, createI18n } from "@/i18n"
import { showFlash } from "@/lib/flash"
import { resolvePage } from "@/inertia"

void createInertiaApp({
  progress: { color: "var(--primary)", delay: 150 },
  resolve: resolvePage,
  setup({ el, App, props }) {
    const initial = props.initialPage.props as unknown as SharedProps
    const i18n = createI18n(initial.locale, initial.translations ?? {})
    let loaded = `${initial.locale}:${initial.i18nVersion}`

    // Route helpers fill :locale from the current language (typelizer URL defaults).
    setUrlDefaults(() => ({ locale: i18n.language }))

    // Tell the server which catalogue we hold; it sends `translations` only when it changed.
    router.on("before", (event) => {
      event.detail.visit.headers["X-I18n"] = loaded
    })
    // After every server response (including redirects to the same page): switch the
    // catalogue when the server sent a new one (language change, admin edit).
    router.on("success", (event) => {
      const shared = event.detail.page.props as unknown as SharedProps
      if (shared.translations) {
        applyTranslations(i18n, shared.locale, shared.translations)
        loaded = `${shared.locale}:${shared.i18nVersion}`
        document.documentElement.lang = shared.locale
      }
    })

    // Follow the device's light/dark setting live when the user chose "system".
    window
      .matchMedia("(prefers-color-scheme: dark)")
      .addEventListener("change", () => applyAppearance(readAppearance()))

    // Flash after redirects: once for the first page, then after every server response.
    router.on("success", (event) => showFlash((event.detail.page.props as unknown as SharedProps).flash))
    setTimeout(() => showFlash(initial.flash), 0)

    const app = (
      <StrictMode>
        <I18nextProvider i18n={i18n}>
          <AppProviders>
            <App {...props} />
          </AppProviders>
        </I18nextProvider>
      </StrictMode>
    )

    // SSR pages arrive with the rendered DOM inside #app (Inertia sets no marker
    // attribute): hydrate them. CSR pages arrive with an empty #app.
    if (el.hasChildNodes()) hydrateRoot(el, app)
    else createRoot(el).render(app)
  },
})
