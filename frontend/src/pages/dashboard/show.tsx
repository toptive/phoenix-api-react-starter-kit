import { useTranslation } from "react-i18next"
import { useAppConfig } from "@/api/hooks/bootstrap"
import { PageHeader } from "@/components/app/page-header"
export default function DashboardPage() {
  const { t } = useTranslation()
  const { auth } = useAppConfig()
  return (
    <>
      <title>{t("nav.home")}</title>
      <PageHeader
        title={t("dashboard.greeting", { name: auth?.user.name })}
        description={t("dashboard.lead", { organization: auth?.organization.name })}
      />
    </>
  )
}
