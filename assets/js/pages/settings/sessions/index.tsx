import { Head, router } from "@inertiajs/react"
import { MonitorSmartphoneIcon } from "lucide-react"
import { useTranslation } from "react-i18next"

import { ConfirmDialog } from "@/components/app/confirm-dialog"
import { SettingsSection } from "@/components/app/settings-section"
import { StatusBadge } from "@/components/app/status-badge"
import { Button } from "@/components/ui/button"
import { formatDateTime } from "@/lib/format"
import { routes } from "@/generated/routes"
import type { SettingsSessionsIndexProps } from "@/generated/pages"


/** "Where am I signed in?" — one row per device, sign out the ones you don't recognise. */
export default function SessionsIndex({ sessions, currentSessionId, locale }: SettingsSessionsIndexProps) {
  const { t } = useTranslation()

  return (
    <SettingsSection title={t("settings.sessions.title")} description={t("settings.sessions.lead")}>
      <Head title={t("settings.sessions.title")} />
      <ul className="divide-y rounded-xl border bg-card">
        {sessions.map((session) => (
          <li key={session.id} className="flex items-center gap-4 p-4">
            <MonitorSmartphoneIcon className="size-5 shrink-0 text-muted-foreground" aria-hidden="true" />
            <div className="min-w-0 flex-1">
              <p className="truncate font-medium">{describeDevice(session.userAgent) ?? t("settings.sessions.unknown_device")}</p>
              <p className="text-sm text-muted-foreground">
                {t("settings.sessions.signed_in_at", { date: formatDateTime(session.insertedAt, locale) })}
                {session.ipAddress ? ` · ${session.ipAddress}` : ""}
              </p>
            </div>
            {session.id === currentSessionId ? (
              <StatusBadge tone="success">{t("settings.sessions.this_device")}</StatusBadge>
            ) : (
              <ConfirmDialog
                trigger={<Button variant="outline" size="sm">{t("settings.sessions.sign_out")}</Button>}
                title={t("settings.sessions.confirm_title")}
                description={t("settings.sessions.confirm_body")}
                confirmLabel={t("settings.sessions.sign_out")}
                onConfirm={() => router.delete(routes.settingsSession.delete(session.id).url, { preserveScroll: true })}
              />
            )}
          </li>
        ))}
      </ul>
    </SettingsSection>
  )
}

function describeDevice(userAgent: string | null): string | null {
  if (!userAgent) return null
  const browser = /Edg\//.test(userAgent) ? "Edge" : /Chrome\//.test(userAgent) ? "Chrome" : /Firefox\//.test(userAgent) ? "Firefox" : /Safari\//.test(userAgent) ? "Safari" : null
  const os = /iPhone|iPad/.test(userAgent) ? "iOS" : /Android/.test(userAgent) ? "Android" : /Mac OS X/.test(userAgent) ? "macOS" : /Windows/.test(userAgent) ? "Windows" : /Linux/.test(userAgent) ? "Linux" : null
  return [browser, os].filter(Boolean).join(" · ") || null
}
