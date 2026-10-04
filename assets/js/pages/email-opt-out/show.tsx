import { Head, Link, useForm } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { AuthHeading } from "@/components/app/auth-card"
import { Button } from "@/components/ui/button"
import { routes } from "@/generated/routes"
import type { EmailOptOutShowProps } from "@/generated/pages"

/** A button, not an automatic unsubscribe: email scanners that open links change nothing. */
export default function EmailOptOutShow({ token, email, subscribed }: EmailOptOutShowProps) {
  const { t } = useTranslation()
  const form = useForm({})

  if (!subscribed) {
    return (
      <>
        <Head title={t("email_opt_out.done_title")} />
        <AuthHeading title={t("email_opt_out.done_title")} description={t("email_opt_out.done_lead", { email })} />
        <p className="mb-6 text-sm text-muted-foreground">{t("email_opt_out.resubscribe")}</p>
        <div className="grid gap-3">
          <Button asChild size="lg" variant="outline" className="w-full">
            <Link href={routes.settingsEmailPreference.edit().url}>{t("email_opt_out.settings")}</Link>
          </Button>
          <Button asChild size="lg" variant="ghost" className="w-full">
            <Link href={routes.home.show().url}>{t("email_opt_out.home")}</Link>
          </Button>
        </div>
      </>
    )
  }

  return (
    <>
      <Head title={t("email_opt_out.title")} />
      <AuthHeading title={t("email_opt_out.title")} description={t("email_opt_out.lead", { email })} />
      <p className="mb-6 text-sm text-muted-foreground">{t("email_opt_out.still_sent")}</p>
      <form
        onSubmit={(event) => {
          event.preventDefault()
          form.post(routes.emailOptOut.create({ token }).url)
        }}
      >
        <Button type="submit" size="lg" className="w-full" disabled={form.processing}>
          {t("email_opt_out.submit")}
        </Button>
      </form>
    </>
  )
}
