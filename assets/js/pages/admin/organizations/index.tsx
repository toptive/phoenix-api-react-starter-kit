import { Head, Link } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { DataTable } from "@/components/app/data-table"
import { PageHeader } from "@/components/app/page-header"
import { Pagination } from "@/components/app/pagination"
import { SearchForm } from "@/components/app/search-form"
import { formatDate } from "@/lib/format"
import { routes } from "@/generated/routes"
import { compact } from "@/lib/query"
import type { AdminOrganizationsIndexProps } from "@/generated/pages"


export default function AdminOrganizationsIndex({ organizations, pagination, q, locale }: AdminOrganizationsIndexProps) {
  const { t } = useTranslation()

  return (
    <>
      <Head title={t("admin.organizations.title")} />
      <PageHeader title={t("admin.organizations.title")} description={t("admin.organizations.lead")} />
      <div className="mb-4">
        <SearchForm href={(query) => routes.adminOrganization.index({ query: compact({ q: query }) }).url} initial={q} label={t("admin.organizations.search")} />
      </div>
      <DataTable
        rows={organizations}
        rowKey={(org) => org.id}
        empty={<p className="text-muted-foreground">{t("admin.empty")}</p>}
        columns={[
          {
            header: t("fields.organization_name"),
            cell: (org) => (
              <Link href={routes.adminOrganization.show(org.id).url} className="font-medium hover:underline">
                {org.name}
              </Link>
            ),
          },
          { header: t("admin.organizations.members"), cell: (org) => org.members, className: "tabular-nums" },
          { header: t("admin.users.joined"), cell: (org) => formatDate(org.insertedAt, locale) },
        ]}
      />
      <Pagination meta={pagination} href={(page) => routes.adminOrganization.index({ query: compact({ q, page }) }).url} />
    </>
  )
}
