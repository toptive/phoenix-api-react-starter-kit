import { Head, Link } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { PageHeader } from "@/components/app/page-header"
import { routes } from "@/generated/routes"
import type { AdminDashboardShowProps } from "@/generated/pages"


export default function AdminDashboard({ stats }: AdminDashboardShowProps) {
  const { t } = useTranslation()

  const tiles = [
    { label: t("admin.stats.users"), value: stats.users, href: routes.adminUser.index().url },
    { label: t("admin.stats.organizations"), value: stats.organizations, href: routes.adminOrganization.index().url },
  ]

  return (
    <>
      <Head title={t("admin.title")} />
      <PageHeader title={t("admin.title")} description={t("admin.lead")} />
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {tiles.map((tile) => (
          <Link key={tile.href} href={tile.href} className="rounded-xl border bg-card p-5 hover:border-primary/50">
            <p className="text-sm text-muted-foreground">{tile.label}</p>
            <p className="mt-1 text-3xl font-bold tabular-nums">{tile.value}</p>
          </Link>
        ))}
      </div>
    </>
  )
}
