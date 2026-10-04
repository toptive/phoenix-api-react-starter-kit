import { useSearch } from "@tanstack/react-router"
import { useAdminUsers } from "@/api/hooks/admin"
import { QueryState } from "@/components/app/query-state"
import { paths } from "@/lib/paths"
import { listSearchSchema } from "@/schemas/search"
import { listHref } from "@/lib/pagination"
import { Link } from "@/components/app/link"
import { useTranslation } from "react-i18next"

import { DataTable } from "@/components/app/data-table"
import { PageHeader } from "@/components/app/page-header"
import { Pagination } from "@/components/app/pagination"
import { SearchForm } from "@/components/app/search-form"
import { StatusBadge } from "@/components/app/status-badge"
import { formatDate } from "@/lib/format"

export default function AdminUsersIndex() {
  const { t, i18n } = useTranslation()
  const locale = i18n.language
  const search = listSearchSchema.parse(useSearch({ strict: false }))
  const q = search.q
  const query = useAdminUsers(search)
  const users = query.data?.data
  const pagination = query.data?.meta?.pagination
  if (!users) return <QueryState pending={query.isPending} error={query.error} retry={query.refetch} />

  return (
    <>
      <title>{t("admin.users.title")}</title>
      <PageHeader title={t("admin.users.title")} description={t("admin.users.lead")} />
      <div className="mb-4">
        <SearchForm
          key={q}
          href={(query) => listHref(paths.adminUsers, search, { q: query })}
          initial={q}
          label={t("admin.users.search")}
        />
      </div>
      <DataTable
        rows={users}
        rowKey={(user) => user.id}
        empty={<p className="text-muted-foreground">{t("admin.empty")}</p>}
        columns={[
          {
            header: t("fields.email"),
            cell: (user) => (
              <Link
                href={`${paths.adminUsers}/${user.id}`}
                className="inline-flex min-h-11 items-center font-medium hover:underline"
              >
                {user.email}
              </Link>
            ),
          },
          { header: t("admin.users.name"), cell: (user) => user.name },
          {
            header: t("admin.users.role"),
            cell: (user) => (
              <StatusBadge tone={user.role === "superadmin" ? "warning" : "neutral"}>
                {t(`global_roles.${user.role}`)}
              </StatusBadge>
            ),
          },
          {
            header: t("admin.users.confirmed"),
            cell: (user) => (user.confirmedAt ? formatDate(user.confirmedAt, locale) : t("common.no")),
          },
          { header: t("admin.users.joined"), cell: (user) => formatDate(user.insertedAt, locale) },
        ]}
      />
      {pagination && <Pagination meta={pagination} href={(page) => listHref(paths.adminUsers, search, { page })} />}
    </>
  )
}
