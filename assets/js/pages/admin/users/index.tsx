import { Head, Link } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { DataTable } from "@/components/app/data-table"
import { PageHeader } from "@/components/app/page-header"
import { Pagination } from "@/components/app/pagination"
import { SearchForm } from "@/components/app/search-form"
import { StatusBadge } from "@/components/app/status-badge"
import { formatDate } from "@/lib/format"
import { routes } from "@/generated/routes"
import { compact } from "@/lib/query"
import type { AdminUsersIndexProps } from "@/generated/pages"


export default function AdminUsersIndex({ users, pagination, q, locale }: AdminUsersIndexProps) {
  const { t } = useTranslation()

  return (
    <>
      <Head title={t("admin.users.title")} />
      <PageHeader title={t("admin.users.title")} description={t("admin.users.lead")} />
      <div className="mb-4">
        <SearchForm href={(query) => routes.adminUser.index({ query: compact({ q: query }) }).url} initial={q} label={t("admin.users.search")} />
      </div>
      <DataTable
        rows={users}
        rowKey={(user) => user.id}
        empty={<p className="text-muted-foreground">{t("admin.empty")}</p>}
        columns={[
          {
            header: t("fields.email"),
            cell: (user) => (
              <Link href={routes.adminUser.show(user.id).url} className="font-medium hover:underline">
                {user.email}
              </Link>
            ),
          },
          { header: t("admin.users.name"), cell: (user) => user.name },
          { header: t("admin.users.role"), cell: (user) => <StatusBadge tone={user.role === "superadmin" ? "warning" : "neutral"}>{t(`global_roles.${user.role}`)}</StatusBadge> },
          { header: t("admin.users.confirmed"), cell: (user) => (user.confirmedAt ? formatDate(user.confirmedAt, locale) : t("common.no")) },
          { header: t("admin.users.joined"), cell: (user) => formatDate(user.insertedAt, locale) },
        ]}
      />
      <Pagination meta={pagination} href={(page) => routes.adminUser.index({ query: compact({ q, page }) }).url} />
    </>
  )
}
