import { Head, Link } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { buttonVariants } from "@/components/ui/button"
import { routes } from "@/generated/routes"
import type { ErrorsShowProps } from "@/generated/pages"


/** 403 and 404 inside the app: say what happened and where to go. */
export default function ErrorShow({ status, auth }: ErrorsShowProps) {
  const { t } = useTranslation()
  const code = status === 403 ? "403" : "404"

  return (
    <div className="mx-auto max-w-md px-4 py-24 text-center">
      <Head title={t(`errors.page.${code}.title`)} />
      <p className="text-sm font-semibold text-muted-foreground">{code}</p>
      <h1 className="mt-2 text-3xl font-bold">{t(`errors.page.${code}.title`)}</h1>
      <p className="mt-3 text-muted-foreground">{t(`errors.page.${code}.body`)}</p>
      <Link href={auth ? routes.dashboard.show().url : routes.home.show().url} className={buttonVariants({ className: "mt-8" })}>
        {auth ? t("errors.page.dashboard") : t("errors.page.home")}
      </Link>
    </div>
  )
}
