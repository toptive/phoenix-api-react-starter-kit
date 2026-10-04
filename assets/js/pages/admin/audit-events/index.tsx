import { Head } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { DataTable } from "@/components/app/data-table"
import { PageHeader } from "@/components/app/page-header"
import { Pagination } from "@/components/app/pagination"
import { SearchForm } from "@/components/app/search-form"
import { StatusBadge } from "@/components/app/status-badge"
import { formatDateTime } from "@/lib/format"
import { routes } from "@/generated/routes"
import { compact } from "@/lib/query"
import type { AdminAuditEventsIndexProps } from "@/generated/pages"


export default function AdminAuditIndex({ events, pagination, q, locale }: AdminAuditEventsIndexProps) {
  const { t } = useTranslation()

  return (
    <>
      <Head title={t("admin.audit.title")} />
      <PageHeader title={t("admin.audit.title")} description={t("admin.audit.lead")} />
      <div className="mb-4">
        <SearchForm href={(query) => routes.adminAuditEvent.index({ query: compact({ q: query }) }).url} initial={q} label={t("admin.audit.search")} />
      </div>
      <DataTable
        rows={events}
        rowKey={(e) => e.id}
        empty={<p className="text-muted-foreground">{t("admin.empty")}</p>}
        columns={[
          { header: t("admin.audit.when"), cell: (e) => formatDateTime(e.insertedAt, locale), className: "whitespace-nowrap" },
          { header: t("admin.audit.action"), cell: (e) => <code className="text-sm">{e.action}</code> },
          { header: t("admin.audit.subject"), cell: (e) => (e.subjectType ? `${e.subjectType} ${e.subjectId?.slice(0, 8) ?? ""}` : "") },
          { header: t("admin.audit.actor"), cell: (e) => e.actorEmail ?? "" },
          { header: "", cell: (e) => e.impersonatorId && <StatusBadge tone="warning">{t("admin.audit.impersonated")}</StatusBadge> },
        ]}
      />
      <Pagination meta={pagination} href={(page) => routes.adminAuditEvent.index({ query: compact({ q, page }) }).url} />
    </>
  )
}
