import { Head, Link, router, useForm } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { AlertBanner } from "@/components/app/alert-banner"
import { AuthHeading } from "@/components/app/auth-card"
import { Button, buttonVariants } from "@/components/ui/button"
import { routes } from "@/generated/routes"
import type { InvitationsShowProps } from "@/generated/pages"


export default function InvitationShow({ token, invitation, emailMatches, auth }: InvitationsShowProps) {
  const { t } = useTranslation()
  const form = useForm({})

  return (
    <>
      <Head title={t("invitation.title", { organization: invitation.organization })} />
      <AuthHeading
        title={t("invitation.title", { organization: invitation.organization })}
        description={t("invitation.lead", { role: t(`level.${invitation.role}_${invitation.access}`), email: invitation.email })}
      />

      {auth && emailMatches && (
        <Button size="lg" className="w-full" disabled={form.processing} onClick={() => form.post(routes.invitationInvitationAcceptance.create(token).url)}>
          {t("invitation.accept")}
        </Button>
      )}

      {auth && !emailMatches && (
        <AlertBanner
          tone="warning"
          title={t("invitation.other_account", { email: auth.user.email })}
          action={
            <Button variant="outline" size="sm" onClick={() => router.delete(routes.session.delete().url)}>
              {t("nav.sign_out")}
            </Button>
          }
        >
          {t("invitation.other_account_help", { email: invitation.email })}
        </AlertBanner>
      )}

      {!auth && (
        <div className="grid gap-3">
          <Link href={routes.registration.new({ query: { email: invitation.email } }).url} className={buttonVariants({ size: "lg" })}>
            {t("invitation.create_account")}
          </Link>
          <Link href={routes.session.new().url} className={buttonVariants({ size: "lg", variant: "outline" })}>
            {t("invitation.sign_in")}
          </Link>
          <p className="text-sm text-muted-foreground">{t("invitation.guest_help", { email: invitation.email })}</p>
        </div>
      )}
    </>
  )
}
