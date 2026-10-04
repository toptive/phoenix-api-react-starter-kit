import { Link } from "@/components/app/link"
import { useLocation } from "@tanstack/react-router"
import type { ReactNode } from "react"
import { useTranslation } from "react-i18next"

import { useAppConfig } from "@/api/hooks/bootstrap"
import { paths } from "@/lib/paths"
import { cn } from "@/lib/utils"

/** Settings: a list of small pages, grouped by who they affect (you / your organization). */
export function SettingsLayout({ children }: { children: ReactNode }) {
  const { t } = useTranslation()
  const { pathname: url } = useLocation()
  const props = useAppConfig()

  const groups = [
    {
      title: t("settings.group.you"),
      items: [
        { href: paths.profile, label: t("settings.profile.nav") },
        { href: paths.email, label: t("settings.email.nav") },
        { href: paths.password, label: t("settings.password.nav") },
        { href: paths.emailPreferences, label: t("settings.email_preferences.nav") },
        { href: paths.sessions, label: t("settings.sessions.nav") },
        { href: paths.appearance, label: t("settings.appearance.nav") },
        { href: paths.account, label: t("settings.account.nav") },
      ],
    },
    {
      title: props.auth?.organization.name ?? t("settings.group.organization"),
      items: [
        { href: paths.organization, label: t("settings.organization.nav") },
        { href: paths.members, label: t("settings.members.nav") },
        ...(props.flags.billing ? [{ href: paths.billing, label: t("settings.billing.nav") }] : []),
      ],
    },
  ]

  return (
    <div className="grid gap-10 lg:grid-cols-[13rem_1fr]">
      <nav aria-label={t("nav.settings")} className="space-y-6">
        {groups.map((group) => (
          <div key={group.title}>
            <p className="mb-2 px-3 text-sm font-semibold text-muted-foreground">{group.title}</p>
            <ul className="space-y-0.5">
              {group.items.map((item) => (
                <li key={item.href}>
                  <Link
                    href={item.href}
                    className={cn(
                      "flex min-h-11 items-center rounded-md px-3 py-2 text-sm hover:bg-accent hover:text-accent-foreground",
                      url.startsWith(item.href) && "bg-accent font-medium text-accent-foreground",
                    )}
                  >
                    {item.label}
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </nav>
      <div className="max-w-2xl min-w-0">{children}</div>
    </div>
  )
}
