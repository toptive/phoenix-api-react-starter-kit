import { MonitorSmartphoneIcon } from "lucide-react"
import { useNavigate } from "@tanstack/react-router"
import { useTranslation } from "react-i18next"
import { useSessions, useRevokeSession } from "@/api/hooks/settings"
import { SettingsSection } from "@/components/app/settings-section"
import { ConfirmDialog } from "@/components/app/confirm-dialog"
import { QueryState } from "@/components/app/query-state"
import { EmptyState } from "@/components/app/empty-state"
import { StatusBadge } from "@/components/app/status-badge"
import { FormError } from "@/components/app/form-error"
import { Button } from "@/components/ui/button"
import { formatDateTime } from "@/lib/format"
import { describeDevice } from "@/lib/device"
import { paths } from "@/lib/paths"

export default function SessionsIndex() {
  const { t, i18n } = useTranslation()
  const navigate = useNavigate()
  const query = useSessions()
  const revoke = useRevokeSession()
  return (
    <SettingsSection title={t("settings.sessions.title")} description={t("settings.sessions.lead")}>
      <title>{t("settings.sessions.title")}</title>
      <QueryState pending={query.isPending} error={query.error} retry={query.refetch} />
      <FormError error={revoke.error} />
      {query.data?.length === 0 && (
        <EmptyState
          icon={MonitorSmartphoneIcon}
          title={t("settings.sessions.empty_title")}
          description={t("settings.sessions.empty_help")}
          action={
            <Button
              variant="outline"
              onClick={() => {
                void query.refetch()
              }}
            >
              {t("common.retry")}
            </Button>
          }
        />
      )}
      {Boolean(query.data?.length) && (
        <ul className="divide-y rounded-xl border bg-card">
          {query.data!.map((session) => (
            <li key={session.id} className="flex flex-wrap items-center gap-4 p-4">
              <MonitorSmartphoneIcon className="size-5 shrink-0 text-muted-foreground" aria-hidden="true" />
              <div className="min-w-0 flex-1">
                <p className="truncate font-medium">
                  {describeDevice(session.userAgent) ?? t("settings.sessions.unknown_device")}
                </p>
                <p className="text-sm text-muted-foreground">
                  {t("settings.sessions.signed_in_at", { date: formatDateTime(session.insertedAt, i18n.language) })}
                  {session.ipAddress ? ` · ${session.ipAddress}` : ""}
                </p>
              </div>
              {session.current && <StatusBadge tone="success">{t("settings.sessions.this_device")}</StatusBadge>}
              <ConfirmDialog
                trigger={
                  <Button variant="outline" size="sm" disabled={revoke.isPending}>
                    {t("settings.sessions.sign_out")}
                  </Button>
                }
                title={t("settings.sessions.confirm_title")}
                description={t(
                  session.current ? "settings.sessions.confirm_current" : "settings.sessions.confirm_body",
                )}
                confirmLabel={t("settings.sessions.sign_out")}
                onConfirm={() =>
                  revoke.mutate(session.id, {
                    onSuccess: () => {
                      if (session.current) void navigate({ to: paths.signIn })
                    },
                  })
                }
              />
            </li>
          ))}
        </ul>
      )}
    </SettingsSection>
  )
}
