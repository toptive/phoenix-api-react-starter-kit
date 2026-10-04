import { lazy, type ReactNode, Suspense } from "react"

// Loaded after the first paint: public pages do not pay for the toast library up front.
const Toaster = lazy(() => import("@/components/ui/sonner").then((m) => ({ default: m.Toaster })))

/**
 * Providers every page needs, in the browser and in SSR. Tooltips live in the app and
 * admin layouts (TooltipProvider) so the public pages stay light.
 */
export function AppProviders({ children }: { children: ReactNode }) {
  return (
    <>
      {children}
      <Suspense fallback={null}>
        <Toaster position="bottom-right" richColors closeButton />
      </Suspense>
    </>
  )
}
