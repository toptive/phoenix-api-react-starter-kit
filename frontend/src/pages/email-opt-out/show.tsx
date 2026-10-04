import { useParams } from "@tanstack/react-router"
import { useTranslation } from "react-i18next"
import { useEmailSubscription, useOptOut } from "@/api/hooks/email-subscriptions"
import { AuthHeading } from "@/components/app/auth-card"
import { QueryState } from "@/components/app/query-state"
import { FormError } from "@/components/app/form-error"
import { FieldHelp } from "@/components/app/field-help"
import { TextLink } from "@/components/app/text-link"
import { Button } from "@/components/ui/button"
import { paths } from "@/lib/paths"

/** Email scanners may preview this page; only the person's button opts out. */
export default function EmailOptOutShow() {
  const { token = "" } = useParams({ strict: false }) as { token?: string }
  const { t } = useTranslation()
  const query = useEmailSubscription(token)
  const optOut = useOptOut(token)
  if (!query.data) return <QueryState pending={query.isPending} error={query.error} retry={query.refetch} />
  const done = !query.data.subscribed
  return (
    <>
      <title>{t(done ? "email_opt_out.done_title" : "email_opt_out.title")}</title>
      <AuthHeading
        title={t(done ? "email_opt_out.done_title" : "email_opt_out.title")}
        description={t(done ? "email_opt_out.done_lead" : "email_opt_out.lead", { email: query.data.email })}
      />
      {done ? (
        <div className="grid gap-4">
          <FieldHelp>{t("email_opt_out.resubscribe")}</FieldHelp>
          <TextLink href={paths.emailPreferences}>{t("email_opt_out.settings")}</TextLink>
          <TextLink href={paths.home()}>{t("email_opt_out.home")}</TextLink>
        </div>
      ) : (
        <div className="grid gap-4">
          <FieldHelp>{t("email_opt_out.still_sent")}</FieldHelp>
          <Button size="lg" disabled={optOut.isPending} onClick={() => optOut.mutate()}>
            {t("email_opt_out.submit")}
          </Button>
          <FormError error={optOut.error} />
        </div>
      )}
    </>
  )
}
