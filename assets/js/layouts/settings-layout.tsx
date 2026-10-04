import { Link, usePage } from "@inertiajs/react"
import type { ReactNode } from "react"
import { useTranslation } from "react-i18next"

import { useSharedProps } from "@/hooks/use-shared-props"
import { routes } from "@/generated/routes"
import { cn } from "@/lib/utils"

/** Settings: a list of small pages, grouped by who they affect (you / your organization). */
export function SettingsLayout({ children }: { children: ReactNode }) {
  const { t } = useTranslation()
  const { url } = usePage()
  const props = useSharedProps()

  const groups = [
    {
      title: t("settings.group.you"),
      items: [
        { href: routes.settingsProfile.edit().url, label: t("settings.profile.nav") },
        { href: routes.settingsEmail.edit().url, label: t("settings.email.nav") },
        { href: routes.settingsPassword.edit().url, label: t("settings.password.nav") },
        { href: routes.settingsEmailPreference.edit().url, label: t("settings.email_preferences.nav") },
        { href: routes.settingsSession.index().url, label: t("settings.sessions.nav") },
        { href: routes.settingsAppearance.edit().url, label: t("settings.appearance.nav") },
        { href: routes.settingsAccount.edit().url, label: t("settings.account.nav") },
      ],
    },
    {
      title: props.auth?.organization.name ?? t("settings.group.organization"),
      items: [
        { href: routes.settingsOrganization.edit().url, label: t("settings.organization.nav") },
        { href: routes.settingsMembership.index().url, label: t("settings.members.nav") },
        ...(props.flags.billing ? [{ href: routes.settingsBilling.show().url, label: t("settings.billing.nav") }] : []),
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
                      "block rounded-md px-3 py-2 text-sm hover:bg-accent hover:text-accent-foreground",
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
      <div className="min-w-0 max-w-2xl">{children}</div>
    </div>
  )
}
