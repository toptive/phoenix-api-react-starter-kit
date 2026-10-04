import { router } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { Button } from "@/components/ui/button"
import { useSharedProps } from "@/hooks/use-shared-props"
import { routes } from "@/generated/routes"

/** Always visible while a superadmin acts as someone else. */
export function ImpersonationBanner() {
  const { t } = useTranslation()
  const { auth } = useSharedProps()
  if (!auth?.impersonator) return null

  return (
    <div role="status" className="flex flex-wrap items-center justify-center gap-3 bg-highlight px-4 py-2 text-sm text-highlight-foreground">
      <span>{t("impersonation.banner", { email: auth.user.email })}</span>
      <Button size="sm" variant="outline" className="bg-transparent" onClick={() => router.delete(routes.impersonation.delete().url)}>
        {t("impersonation.stop")}
      </Button>
    </div>
  )
}
