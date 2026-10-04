import { renderToString } from "react-dom/server"
import { I18nextProvider } from "react-i18next"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import {
  createRootRoute,
  createRoute,
  createRouter,
  createMemoryHistory,
  RouterProvider,
  Outlet,
} from "@tanstack/react-router"
import { createI18n, bundledLocales } from "@/i18n"
import type { Bootstrap } from "@/api/generated/serializers"
import { qk } from "@/api/query-keys"
import { PublicLayout } from "@/layouts/public-layout"
import HomeShow from "@/pages/home/show"

/** Build-time public defaults; runtime flags and text edits come from bootstrap. */
export async function render(locale = "en") {
  const queryClient = new QueryClient()
  const localeInstance = createI18n(locale)
  const bootstrap: Bootstrap = {
    auth: null,
    locale,
    locales: bundledLocales,
    i18nVersion: "build",
    app: {
      name: localeInstance.t("app.name"),
      tenancy: "multi",
      signupMode: "open",
      emailAvailable: true,
      googleEnabled: false,
      publicUrl: import.meta.env.VITE_PUBLIC_URL ?? "http://localhost:5173",
    },
    flags: { billing: false },
    turnstile: { required: false, siteKey: null },
  }
  queryClient.setQueryData(qk.bootstrap, bootstrap)
  const root = createRootRoute({
    component: () => (
      <PublicLayout>
        <Outlet />
      </PublicLayout>
    ),
  })
  const home = createRoute({ getParentRoute: () => root, path: "/", component: HomeShow })
  const localized = createRoute({ getParentRoute: () => root, path: "/$locale", component: HomeShow })
  const router = createRouter({
    routeTree: root.addChildren([home, localized]),
    history: createMemoryHistory({ initialEntries: [locale === "en" ? "/" : `/${locale}`] }),
  })
  await router.load()
  const html = renderToString(
    <I18nextProvider i18n={localeInstance}>
      <QueryClientProvider client={queryClient}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </I18nextProvider>,
  )
  queryClient.clear()
  return html
}
