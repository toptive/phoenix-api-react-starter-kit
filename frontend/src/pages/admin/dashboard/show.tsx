import { useAdminStats } from "@/api/hooks/admin"
import { QueryState } from "@/components/app/query-state"
import { paths } from "@/lib/paths"
import { Link } from "@/components/app/link"
import { useTranslation } from "react-i18next"

import { PageHeader } from "@/components/app/page-header"

export default function AdminDashboard() {
  const { t } = useTranslation()
  const query = useAdminStats()
  const stats = query.data
  if (!stats) return <QueryState pending={query.isPending} error={query.error} retry={query.refetch} />

  const tiles = [
    { label: t("admin.stats.users"), value: stats.users, href: paths.adminUsers },
    { label: t("admin.stats.organizations"), value: stats.organizations, href: paths.adminOrganizations },
  ]

  return (
    <>
      <title>{t("admin.title")}</title>
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
