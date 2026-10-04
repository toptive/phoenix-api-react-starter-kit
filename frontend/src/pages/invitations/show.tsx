import { useNavigate, useParams } from "@tanstack/react-router"
import { useTranslation } from "react-i18next"
import { useInvitation, useAcceptInvitation } from "@/api/hooks/organizations"
import { ApiError } from "@/api/http"
import { useSignOut } from "@/api/hooks/auth"
import { useAppConfig } from "@/api/hooks/bootstrap"
import { AuthHeading } from "@/components/app/auth-card"
import { AlertBanner } from "@/components/app/alert-banner"
import { FormError } from "@/components/app/form-error"
import { QueryState } from "@/components/app/query-state"
import { Link } from "@/components/app/link"
import { Button, buttonVariants } from "@/components/ui/button"
import { returnPath } from "@/lib/auth-flow"
import { paths } from "@/lib/paths"

export default function InvitationShow() {
  const { token = "" } = useParams({ strict: false }) as { token?: string }
  const { t } = useTranslation()
  const { auth, app } = useAppConfig()
  const navigate = useNavigate()
  const preview = useInvitation(token)
  const accept = useAcceptInvitation()
  const signOut = useSignOut()
  const back = paths.invitation(token)
  const invitation = preview.data
  if (preview.error instanceof ApiError && preview.error.code === "invitation_invalid")
    return <FormError message={t("errors.api.invitation_invalid")} />
  if (!invitation) return <QueryState pending={preview.isPending} error={preview.error} retry={preview.refetch} />
  return (
    <>
      <title>{t("invitation.title", { organization: invitation.organization })}</title>
      <AuthHeading
        title={t("invitation.title", { organization: invitation.organization })}
        description={t("invitation.lead", {
          role: t(`level.${invitation.role}_${invitation.access}`),
          email: invitation.email,
        })}
      />
      {auth && invitation.emailMatches && (
        <Button
          size="lg"
          className="w-full"
          disabled={accept.isPending}
          onClick={() =>
            accept.mutate(token, {
              onSuccess: () => {
                returnPath.clear()
                void navigate({ to: paths.dashboard })
              },
            })
          }
        >
          {t("invitation.accept")}
        </Button>
      )}
      {auth && !invitation.emailMatches && (
        <AlertBanner
          tone="warning"
          title={t("invitation.other_account", { email: auth.user.email })}
          action={
            <Button
              variant="outline"
              disabled={signOut.isPending}
              onClick={() => {
                returnPath.set(back)
                signOut.mutate(undefined, {
                  onSuccess: () => {
                    void navigate({ to: paths.signIn, search: { returnTo: back, email: invitation.email } })
                  },
                })
              }}
            >
              {t("nav.sign_out")}
            </Button>
          }
        >
          {t("invitation.other_account_help", { email: invitation.email })}
        </AlertBanner>
      )}
      {!auth && (
        <div className="grid gap-3">
          {app.signupMode !== "closed" && (
            <Link
              href={`${paths.register}?email=${encodeURIComponent(invitation.email)}&returnTo=${encodeURIComponent(back)}`}
              onClick={() => returnPath.set(back)}
              className={buttonVariants({ size: "lg" })}
            >
              {t("invitation.create_account")}
            </Link>
          )}
          <Link
            href={`${paths.signIn}?returnTo=${encodeURIComponent(back)}&email=${encodeURIComponent(invitation.email)}`}
            onClick={() => returnPath.set(back)}
            className={buttonVariants({ size: "lg", variant: "outline" })}
          >
            {t("invitation.sign_in")}
          </Link>
          <p className="text-sm text-muted-foreground">{t("invitation.guest_help", { email: invitation.email })}</p>
        </div>
      )}
      <FormError
        message={accept.error instanceof ApiError && accept.error.code === "invitation_invalid" ? t("errors.api.invitation_invalid") : undefined}
        error={accept.error ?? signOut.error}
      />
    </>
  )
}
