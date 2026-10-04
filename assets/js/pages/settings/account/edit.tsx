import { Head, Link, router } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { AlertBanner } from "@/components/app/alert-banner"
import { ConfirmDialog } from "@/components/app/confirm-dialog"
import { SettingsSection } from "@/components/app/settings-section"
import { Button } from "@/components/ui/button"
import type { SettingsAccountEditProps } from "@/generated/pages"
import { routes } from "@/generated/routes"

export default function AccountEdit({ blocker }: SettingsAccountEditProps) {
  const { t } = useTranslation()

  return (
    <SettingsSection title={t("settings.account.title")} description={t("settings.account.lead")}>
      <Head title={t("settings.account.title")} />
      {blocker ? (
        <AlertBanner
          tone="warning"
          title={t("settings.account.blocked_title")}
          action={
            blocker.reason === "transfer_ownership" ? (
              <Button asChild variant="outline">
                <Link href={routes.settingsMembership.index().url}>{t("settings.members.nav")}</Link>
              </Button>
            ) : (
              <Button asChild variant="outline">
                <Link href={routes.settingsBilling.show().url}>{t("settings.billing.nav")}</Link>
              </Button>
            )
          }
        >
          {blocker.reason === "transfer_ownership"
            ? t("settings.account.blocked.transfer_ownership", { organization: blocker.organization })
            : t("settings.account.blocked.subscription_active", { organization: blocker.organization })}
        </AlertBanner>
      ) : (
        <AlertBanner
          tone="danger"
          title={t("settings.account.delete_title")}
          action={
            <ConfirmDialog
              trigger={<Button variant="destructive">{t("settings.account.delete")}</Button>}
              title={t("settings.account.confirm_title")}
              description={t("settings.account.confirm_body")}
              confirmLabel={t("settings.account.delete")}
              onConfirm={() => router.delete(routes.settingsAccount.delete().url)}
            />
          }
        >
          {t("settings.account.delete_body")}
        </AlertBanner>
      )}
    </SettingsSection>
  )
}
