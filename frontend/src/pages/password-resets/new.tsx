import { useTranslation } from "react-i18next"
import { useAppConfig } from "@/api/hooks/bootstrap"
import { AuthHeading } from "@/components/app/auth-card"
import { AlertBanner } from "@/components/app/alert-banner"
import { MagicLinkForm } from "@/components/app/magic-link-form"
export default function ForgotPasswordPage() {
  const { t } = useTranslation()
  const { app } = useAppConfig()
  return (
    <>
      <title>{t("auth.password_reset.title")}</title>
      <AuthHeading title={t("auth.password_reset.title")} description={t("auth.password_reset.lead")} />
      {app.emailAvailable ? (
        <MagicLinkForm recovery />
      ) : (
        <AlertBanner tone="warning" title={t("auth.unavailable.title")}>
          {t("auth.unavailable.session_body")}
        </AlertBanner>
      )}
    </>
  )
}
