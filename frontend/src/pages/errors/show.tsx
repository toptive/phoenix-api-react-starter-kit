import { useTranslation } from "react-i18next"
import { Link } from "@/components/app/link"
import { buttonVariants } from "@/components/ui/button"
import { useQueryClient } from "@tanstack/react-query"
import type { Bootstrap } from "@/api/generated/serializers"
import { qk } from "@/api/query-keys"
import { paths } from "@/lib/paths"

export default function ErrorShow({ status = 404 }: { status?: number }) {
  const { t } = useTranslation()
  const data = useQueryClient().getQueryData<Bootstrap>(qk.bootstrap)
  const code = status === 403 ? "403" : status === 404 ? "404" : "500"
  return (
    <div className="mx-auto max-w-md px-4 py-24 text-center">
      <title>{t(`errors.page.${code}.title`)}</title>
      <meta name="robots" content="noindex" />
      <p className="text-sm font-semibold text-muted-foreground">{code}</p>
      <h1 className="mt-2 text-3xl font-bold">{t(`errors.page.${code}.title`)}</h1>
      <p className="mt-3 text-muted-foreground">{t(`errors.page.${code}.body`)}</p>
      <Link href={data?.auth ? paths.dashboard : paths.home()} className={buttonVariants({ className: "mt-8" })}>
        {t(data?.auth ? "errors.page.dashboard" : "errors.page.home")}
      </Link>
    </div>
  )
}
