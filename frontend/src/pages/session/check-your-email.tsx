import { useSearch } from "@tanstack/react-router"
import { useTranslation } from "react-i18next"
import { AuthHeading } from "@/components/app/auth-card"
import { AlertBanner } from "@/components/app/alert-banner"
import { TextLink } from "@/components/app/text-link"
import { paths } from "@/lib/paths"
export default function CheckYourEmailPage() {
  const { t } = useTranslation()
  const search = useSearch({ strict: false }) as { email?: string }
  return (
    <>
      <title>{t("auth.session.link_sent_title")}</title>
      <AuthHeading title={t("auth.session.link_sent_title")} />
      <AlertBanner tone="success" title={t("auth.check_email.title")}>
        {t("auth.session.link_sent_body", { email: search.email ?? "" })}
      </AlertBanner>
      <p className="mt-6">
        <TextLink href={paths.signIn}>{t("nav.sign_in")}</TextLink>
      </p>
    </>
  )
}
