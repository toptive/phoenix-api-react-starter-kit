import { useParams, useNavigate } from "@tanstack/react-router"
import { useTranslation } from "react-i18next"
import { useEmailConfirmation, useApplyEmailConfirmation } from "@/api/hooks/auth"
import { QueryState } from "@/components/app/query-state"
import { TextLink } from "@/components/app/text-link"
import { AuthHeading } from "@/components/app/auth-card"
import { FormError } from "@/components/app/form-error"
import { Button } from "@/components/ui/button"
import { paths } from "@/lib/paths"
export default function EmailConfirmationPage() {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const { token = "" } = useParams({ strict: false }) as { token?: string }
  const preview = useEmailConfirmation(token)
  const confirm = useApplyEmailConfirmation()
  if (!preview.data)
    return (
      <>
        <QueryState pending={preview.isPending} error={preview.error} retry={preview.refetch} />
        <TextLink href={paths.email}>{t("settings.email_confirmation.request_new")}</TextLink>
      </>
    )
  return (
    <>
      <title>{t("settings.email_confirmation.title")}</title>
      <AuthHeading
        title={t("settings.email_confirmation.title")}
        description={t("settings.email_confirmation.lead", { email: preview.data?.email })}
      />
      <Button
        size="lg"
        disabled={confirm.isPending}
        onClick={() =>
          confirm.mutate(token, {
            onSuccess: () => {
              void navigate({ to: paths.profile })
            },
          })
        }
      >
        {t("settings.email_confirmation.submit")}
      </Button>
      <FormError error={confirm.error} />
    </>
  )
}
