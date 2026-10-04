import { createInertiaApp } from "@inertiajs/react"
import { renderToString } from "react-dom/server"
import { I18nextProvider } from "react-i18next"

import { AppProviders } from "@/components/app/app-providers"
import type { SharedProps } from "@/generated/pages"
import { setUrlDefaults } from "@/generated/routes"
import { createI18n } from "@/i18n"
import { resolvePage } from "@/inertia"

type Page = NonNullable<Parameters<typeof createInertiaApp>[0]["page"]>

/**
 * Called by the Node worker that Inertia.SSR starts (priv/ssr/ssr.js, CommonJS).
 * Only public pages ask for SSR (render_public/3); one i18n instance per render.
 */
export function render(page: Page) {
  return createInertiaApp({
    page,
    render: renderToString,
    resolve: resolvePage,
    setup({ App, props }) {
      const shared = props.initialPage.props as unknown as SharedProps
      const i18n = createI18n(shared.locale, shared.translations ?? {})
      // Set right before the synchronous renderToString of this page, so concurrent
      // renders in the worker never see another page's locale.
      setUrlDefaults({ locale: shared.locale })

      return (
        <I18nextProvider i18n={i18n}>
          <AppProviders>
            <App {...props} />
          </AppProviders>
        </I18nextProvider>
      )
    },
  })
}
