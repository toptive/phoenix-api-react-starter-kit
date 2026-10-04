import { useSearch } from "@tanstack/react-router"
import { useAdminOrganizations } from "@/api/hooks/admin"
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
import { formatDate } from "@/lib/format"

export default function AdminOrganizationsIndex() {
  const { t, i18n } = useTranslation()
  const locale = i18n.language
  const search = listSearchSchema.parse(useSearch({ strict: false }))
  const q = search.q
  const query = useAdminOrganizations(search)
  const organizations = query.data?.data
  const pagination = query.data?.meta?.pagination
  if (!organizations) return <QueryState pending={query.isPending} error={query.error} retry={query.refetch} />

  return (
    <>
      <title>{t("admin.organizations.title")}</title>
      <PageHeader title={t("admin.organizations.title")} description={t("admin.organizations.lead")} />
      <div className="mb-4">
        <SearchForm
          key={q}
          href={(query) => listHref(paths.adminOrganizations, search, { q: query })}
          initial={q}
          label={t("admin.organizations.search")}
        />
      </div>
      <DataTable
        rows={organizations}
        rowKey={(org) => org.id}
        empty={<p className="text-muted-foreground">{t("admin.empty")}</p>}
        columns={[
          {
            header: t("fields.organization_name"),
            cell: (org) => (
              <Link
                href={`${paths.adminOrganizations}/${org.id}`}
                className="inline-flex min-h-11 items-center font-medium hover:underline"
              >
                {org.name}
              </Link>
            ),
          },
          { header: t("admin.organizations.members"), cell: (org) => org.members, className: "tabular-nums" },
          { header: t("admin.users.joined"), cell: (org) => formatDate(org.insertedAt, locale) },
        ]}
      />
      {pagination && (
        <Pagination meta={pagination} href={(page) => listHref(paths.adminOrganizations, search, { page })} />
      )}
    </>
  )
}
