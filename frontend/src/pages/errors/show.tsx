import { useTranslation } from "react-i18next"
import { ShieldXIcon, SearchXIcon, TriangleAlertIcon, ArrowLeftIcon, RotateCwIcon } from "lucide-react"
import { Link } from "@/components/app/link"
import { Button, buttonVariants } from "@/components/ui/button"
import { useQueryClient } from "@tanstack/react-query"
import type { Bootstrap } from "@/api/generated/serializers"
import { qk } from "@/api/query-keys"
import { paths } from "@/lib/paths"

export default function ErrorShow({ status = 404, onRetry }: { status?: number; onRetry?: () => void }) {
  const { t } = useTranslation()
  const data = useQueryClient().getQueryData<Bootstrap>(qk.bootstrap)
  const code = status === 403 ? "403" : status === 404 ? "404" : "500"
  const Icon = code === "403" ? ShieldXIcon : code === "404" ? SearchXIcon : TriangleAlertIcon
  return (
    <div className="grid min-h-[65dvh] place-items-center px-4 py-16">
      <title>{t(`errors.page.${code}.title`)}</title>
      <meta name="robots" content="noindex" />
      <div className="w-full max-w-lg rounded-2xl border bg-card p-8 text-center shadow-sm sm:p-12">
        <div className="mx-auto mb-6 grid size-16 place-items-center rounded-full bg-muted">
          <Icon aria-hidden="true" className="size-7 text-muted-foreground" />
        </div>
        <p className="text-sm font-semibold tracking-widest text-muted-foreground">{code}</p>
        <h1 className="mt-3 text-3xl font-bold tracking-tight">{t(`errors.page.${code}.title`)}</h1>
        <p className="mt-4 text-muted-foreground">{t(`errors.page.${code}.body`)}</p>
        <div className="mt-8 flex flex-wrap justify-center gap-3">
          {code === "500" && (
            <Button onClick={onRetry ?? (() => window.location.reload())}>
              <RotateCwIcon aria-hidden="true" />
              {t("common.retry")}
            </Button>
          )}
          <Link
            href={data?.auth ? paths.dashboard : paths.home()}
            className={buttonVariants({ variant: code === "500" ? "outline" : "default" })}
          >
            <ArrowLeftIcon aria-hidden="true" />
            {t(data?.auth ? "errors.page.dashboard" : "errors.page.home")}
          </Link>
        </div>
      </div>
    </div>
  )
}
