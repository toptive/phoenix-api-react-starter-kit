import { useNavigate, useParams } from "@tanstack/react-router"
import { useTranslation } from "react-i18next"
import { useMagicLink, useConsumeMagicLink, useSudo } from "@/api/hooks/auth"
import { useAppConfig } from "@/api/hooks/bootstrap"
import { AuthHeading } from "@/components/app/auth-card"
import { FormError } from "@/components/app/form-error"
import { TextLink } from "@/components/app/text-link"
import { Button } from "@/components/ui/button"
import { destinationAfterAuth, returnPath } from "@/lib/auth-flow"
import { paths } from "@/lib/paths"

/** GET only previews; only the person's button consumes a single-use link. */
export default function ConfirmEmailPage() {
  const { token = "" } = useParams({ strict: false }) as { token?: string }
  const { t } = useTranslation()
  const { auth } = useAppConfig()
  const navigate = useNavigate()
  const preview = useMagicLink(token)
  const consume = useConsumeMagicLink()
  const sudo = useSudo()
  const reauth = auth?.user.email === preview.data?.email && Boolean(returnPath.get())
  const complete = (destination?: string) => {
    const success = () => {
      const next = destination ?? destinationAfterAuth()
      returnPath.clear()
      void navigate({ to: next })
    }
    if (reauth) sudo.mutate({ magicLinkToken: token }, { onSuccess: success })
    else consume.mutate(token, { onSuccess: success })
  }
  if (preview.isPending) return <p role="status">{t("common.loading")}</p>
  if (preview.error || !preview.data)
    return (
      <>
        <FormError error={preview.error} />
        <TextLink href={paths.signIn}>{t("auth.session.send_link")}</TextLink>
      </>
    )
  return (
    <>
      <title>{t("auth.magic_link.title")}</title>
      <AuthHeading
        title={t(preview.data.confirmed ? "auth.magic_link.title" : "auth.magic_link.confirm_title")}
        description={t("auth.magic_link.lead", { email: preview.data.email })}
      />
      <form
        onSubmit={(event) => {
          event.preventDefault()
          complete()
        }}
      >
        <Button type="submit" size="lg" className="w-full" disabled={consume.isPending || sudo.isPending}>
          {t(preview.data.confirmed ? "auth.magic_link.submit" : "auth.magic_link.confirm_submit")}
        </Button>
        <FormError error={consume.error ?? sudo.error} />
      </form>
    </>
  )
}
