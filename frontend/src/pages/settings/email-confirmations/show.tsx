import { useParams, useNavigate } from "@tanstack/react-router"
import { useTranslation } from "react-i18next"
import { useEmailConfirmation, useApplyEmailConfirmation } from "@/api/hooks/auth"
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
  if (preview.isPending) return <p role="status">{t("common.loading")}</p>
  if (preview.error) return <FormError error={preview.error} />
  return (
    <>
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
