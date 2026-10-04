import type { LegalPage } from "@/api/generated/serializers"
import { qk } from "@/api/query-keys"
import { NetworkStatus } from "@/components/app/network-status"
import { Toaster } from "@/components/ui/sonner"
import "./styles/app.css"
import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { QueryClientProvider } from "@tanstack/react-query"
import { RouterProvider } from "@tanstack/react-router"
import { I18nextProvider } from "react-i18next"
import { clearApiFailure } from "@/lib/api-failure"
import { i18n } from "@/i18n"
import { router } from "@/router"
import { queryClient } from "@/lib/query-client"
import { applyAppearance, readAppearance } from "@/hooks/use-appearance"
import { setUnauthorizedHandler, TOKEN_KEY, ADMIN_TOKEN_KEY } from "@/api/http"

router.subscribe("onBeforeNavigate", clearApiFailure)
setUnauthorizedHandler(() => {
  const returnTo = window.location.pathname + window.location.search
  void queryClient.cancelQueries().then(() => {
    queryClient.removeQueries()
    void router.navigate({ to: "/session/new", search: { returnTo }, replace: true })
  })
})
window.addEventListener("storage", (event) => {
  if (event.key === TOKEN_KEY || event.key === ADMIN_TOKEN_KEY) {
    void queryClient.cancelQueries().then(() => {
      queryClient.removeQueries()
      void router.invalidate()
    })
  }
})
window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => applyAppearance(readAppearance()))
// The landing arrives prerendered. Replace it after bootstrap resolves into the SPA shell.
const element = document.getElementById("root")
if (!element) throw new Error("Missing application root")
const publicLegal = document.getElementById("prerendered-legal")
if (publicLegal?.textContent) {
  try {
    const { locale, page } = JSON.parse(publicLegal.textContent) as { locale: string; page: LegalPage }
    if (typeof locale === "string" && typeof page?.slug === "string")
      queryClient.setQueryData(qk.legal(page.slug, locale), page, { updatedAt: 0 })
  } catch {
    /* A stale static artifact can always load through the API. */
  }
}
document.querySelectorAll("[data-prerendered]").forEach((metadata) => metadata.remove())
createRoot(element).render(
  <StrictMode>
    <I18nextProvider i18n={i18n}>
      <QueryClientProvider client={queryClient}>
        <NetworkStatus />
        <RouterProvider router={router} />
        <Toaster position="bottom-right" richColors closeButton />
      </QueryClientProvider>
    </I18nextProvider>
  </StrictMode>,
)
