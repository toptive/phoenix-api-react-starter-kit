import { useSearch } from "@tanstack/react-router"
import { useAuditEvents } from "@/api/hooks/admin"
import { QueryState } from "@/components/app/query-state"
import { paths } from "@/lib/paths"
import { listSearchSchema } from "@/schemas/search"
import { listHref } from "@/lib/pagination"

import { useTranslation } from "react-i18next"

import { DataTable } from "@/components/app/data-table"
import { PageHeader } from "@/components/app/page-header"
import { Pagination } from "@/components/app/pagination"
import { SearchForm } from "@/components/app/search-form"
import { StatusBadge } from "@/components/app/status-badge"
import { formatDateTime } from "@/lib/format"

export default function AdminAuditIndex() {
  const { t, i18n } = useTranslation()
  const locale = i18n.language
  const search = listSearchSchema.parse(useSearch({ strict: false }))
  const q = search.q
  const query = useAuditEvents(search)
  const events = query.data?.data
  const pagination = query.data?.meta?.pagination
  if (!events) return <QueryState pending={query.isPending} error={query.error} retry={query.refetch} />

  return (
    <>
      <title>{t("admin.audit.title")}</title>
      <PageHeader title={t("admin.audit.title")} description={t("admin.audit.lead")} />
      <div className="mb-4">
        <SearchForm
          key={q}
          href={(query) => listHref(paths.adminAuditEvents, search, { q: query })}
          initial={q}
          label={t("admin.audit.search")}
        />
      </div>
      <DataTable
        rows={events}
        rowKey={(e) => e.id}
        empty={<p className="text-muted-foreground">{t("admin.empty")}</p>}
        columns={[
          {
            header: t("admin.audit.when"),
            cell: (e) => formatDateTime(e.insertedAt, locale),
            className: "whitespace-nowrap",
          },
          { header: t("admin.audit.action"), cell: (e) => <code className="text-sm">{e.action}</code> },
          {
            header: t("admin.audit.subject"),
            cell: (e) => (e.subjectType ? `${e.subjectType} ${e.subjectId?.slice(0, 8) ?? ""}` : ""),
          },
          { header: t("admin.audit.actor"), cell: (e) => e.actorEmail ?? "" },
          {
            header: t("admin.audit.details"),
            cell: (e) => (
              <details>
                <summary className="min-h-11 cursor-pointer py-2">{t("admin.audit.details")}</summary>
                <dl className="space-y-2 text-sm">
                  {[
                    ["admin.audit.event_id", e.id],
                    ["admin.audit.actor_id", e.actorId],
                    ["admin.audit.organization_id", e.organizationId],
                    ["admin.audit.subject_id", e.subjectId],
                    ["admin.audit.impersonator_id", e.impersonatorId],
                  ].map(
                    ([label, value]) =>
                      value && (
                        <div key={label}>
                          <dt className="text-muted-foreground">{t(label!)}</dt>
                          <dd className="break-all">{value}</dd>
                        </div>
                      ),
                  )}
                </dl>
                <pre className="mt-3 max-w-sm overflow-x-auto text-xs break-all whitespace-pre-wrap">
                  {JSON.stringify(e.metadata, null, 2)}
                </pre>
              </details>
            ),
          },
          {
            header: t("admin.audit.impersonated"),
            cell: (e) => e.impersonatorId && <StatusBadge tone="warning">{t("admin.audit.impersonated")}</StatusBadge>,
          },
        ]}
      />
      {pagination && (
        <Pagination meta={pagination} href={(page) => listHref(paths.adminAuditEvents, search, { page })} />
      )}
    </>
  )
}
