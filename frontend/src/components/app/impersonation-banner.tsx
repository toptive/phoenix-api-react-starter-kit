import { useNavigate } from "@tanstack/react-router"
import { useTranslation } from "react-i18next"

import { FormError } from "./form-error"
import { Button } from "@/components/ui/button"
import { getToken } from "@/api/http"
import { useBootstrap } from "@/api/hooks/bootstrap"
import { paths } from "@/lib/paths"
import { useStopImpersonation } from "@/api/hooks/auth"

/** Always visible while a superadmin acts as someone else. */
export function ImpersonationBanner() {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const stop = useStopImpersonation()
  const auth = useBootstrap(Boolean(getToken())).data?.auth
  if (!auth?.impersonator) return null

  return (
    <div
      role="status"
      className="sticky top-0 z-50 flex flex-wrap items-center justify-center gap-3 bg-highlight px-4 py-2 text-sm text-highlight-foreground"
    >
      <span>{t("impersonation.banner", { email: auth.user.email })}</span>
      <Button
        variant="outline"
        disabled={stop.isPending}
        className="bg-transparent"
        onClick={() =>
          stop.mutate(undefined, {
            onSuccess: () => {
              void navigate({ to: paths.adminUsers })
            },
          })
        }
      >
        {t("impersonation.stop")}
      </Button>
      <FormError error={stop.error} />
    </div>
  )
}
