import { useNavigate } from "@tanstack/react-router"
import { useTranslation } from "react-i18next"
import { useAccountDeletion, useDeleteAccount } from "@/api/hooks/settings"
import { useSwitchOrganization } from "@/api/hooks/auth"
import { useAppConfig } from "@/api/hooks/bootstrap"
import { ApiError } from "@/api/http"
import { SettingsSection } from "@/components/app/settings-section"
import { QueryState } from "@/components/app/query-state"
import { FormError } from "@/components/app/form-error"
import { AlertBanner } from "@/components/app/alert-banner"
import { ConfirmDialog } from "@/components/app/confirm-dialog"
import { Button } from "@/components/ui/button"
import { paths } from "@/lib/paths"

export default function AccountEdit() {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const { auth } = useAppConfig()
  const query = useAccountDeletion()
  const remove = useDeleteAccount()
  const switchOrg = useSwitchOrganization()
  const refused =
    remove.error instanceof ApiError &&
    ["transfer_ownership", "subscription_active"].includes(remove.error.code) &&
    typeof remove.error.details.organization === "string"
      ? { reason: remove.error.code, organization: remove.error.details.organization }
      : null
  const blocker = refused ?? query.data?.blocker
  return (
    <SettingsSection title={t("settings.account.title")} description={t("settings.account.lead")}>
      <title>{t("settings.account.title")}</title>
      <QueryState pending={query.isPending} error={query.error} retry={query.refetch} />
      {query.data &&
        (blocker ? (
          <AlertBanner
            tone="warning"
            title={t("settings.account.blocked_title")}
            action={
              <Button
                variant="outline"
                disabled={switchOrg.isPending}
                onClick={async () => {
                  const target = auth?.organizations.find((organization) => organization.name === blocker.organization)
                  try {
                    if (target && target.id !== auth?.organization.id) await switchOrg.mutateAsync(target.id)
                    void navigate({ to: blocker.reason === "transfer_ownership" ? paths.members : paths.billing })
                  } catch {
                    /* The mutation error appears below. */
                  }
                }}
              >
                {t(blocker.reason === "transfer_ownership" ? "settings.members.nav" : "settings.billing.nav")}
              </Button>
            }
          >
            {t(`settings.account.blocked.${blocker.reason}`, { organization: blocker.organization })}
          </AlertBanner>
        ) : (
          <AlertBanner
            tone="danger"
            title={t("settings.account.delete_title")}
            action={
              <ConfirmDialog
                trigger={
                  <Button variant="destructive" disabled={remove.isPending}>
                    {t("settings.account.delete")}
                  </Button>
                }
                title={t("settings.account.confirm_title")}
                description={t("settings.account.confirm_consequence")}
                confirmLabel={t("settings.account.delete")}
                onConfirm={() =>
                  remove.mutate(undefined, {
                    onSuccess: () => {
                      void navigate({ to: paths.home() })
                    },
                  })
                }
              />
            }
          >
            {t("settings.account.delete_body")}
          </AlertBanner>
        ))}
      <FormError error={remove.error ?? switchOrg.error} />
      {query.data && blocker && (
        <Button
          className="mt-6"
          variant="outline"
          disabled={query.isFetching || remove.isPending}
          onClick={() => {
            remove.reset()
            void query.refetch()
          }}
        >
          {t("settings.account.check_again")}
        </Button>
      )}
    </SettingsSection>
  )
}
