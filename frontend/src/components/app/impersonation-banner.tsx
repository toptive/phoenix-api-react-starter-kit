import { useNavigate } from "@tanstack/react-router"
import { useTranslation } from "react-i18next"

import { Button } from "@/components/ui/button"
import { useAppConfig } from "@/api/hooks/bootstrap"
import { paths } from "@/lib/paths"
import { useStopImpersonation } from "@/api/hooks/auth"

/** Always visible while a superadmin acts as someone else. */
export function ImpersonationBanner() {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const stop = useStopImpersonation()
  const { auth } = useAppConfig()
  if (!auth?.impersonator) return null

  return (
    <div role="status" className="flex flex-wrap items-center justify-center gap-3 bg-highlight px-4 py-2 text-sm text-highlight-foreground">
      <span>{t("impersonation.banner", { email: auth.user.email })}</span>
      <Button size="sm" variant="outline" className="bg-transparent" onClick={() => stop.mutate(undefined, { onSuccess: () => { void navigate({ to: paths.adminUsers }) } })}>
        {t("impersonation.stop")}
      </Button>
    </div>
  )
}
