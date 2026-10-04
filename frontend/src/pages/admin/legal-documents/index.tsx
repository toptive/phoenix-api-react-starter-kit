import { useLegalDocuments } from "@/api/hooks/admin"
import { QueryState } from "@/components/app/query-state"
import { paths } from "@/lib/paths"
import { Link } from "@/components/app/link"
import { useTranslation } from "react-i18next"

import { PageHeader } from "@/components/app/page-header"
import { StatusBadge } from "@/components/app/status-badge"

export default function AdminLegalIndex() {
  const { t } = useTranslation()
  const query = useLegalDocuments()
  const documents = query.data
  if (!documents) return <QueryState pending={query.isPending} error={query.error} retry={query.refetch} />

  return (
    <>
      <title>{t("admin.legal.title")}</title>
      <PageHeader title={t("admin.legal.title")} description={t("admin.legal.lead")} />
      <ul className="divide-y rounded-xl border bg-card">
        {documents.map((doc) => {
          const published = doc.versions.find((v) => v.id === doc.publishedVersionId)
          return (
            <li key={doc.id} className="flex items-center gap-4 p-4">
              <Link
                href={`${paths.adminLegalDocuments}/${doc.slug}`}
                className="flex min-h-11 flex-1 items-center font-medium hover:underline"
              >
                {t(`legal.${doc.slug}`)}
              </Link>
              {published ? (
                <StatusBadge tone="success">
                  {t("admin.legal.published_version", { version: published.number })}
                </StatusBadge>
              ) : (
                <StatusBadge tone="warning">{t("admin.legal.not_published")}</StatusBadge>
              )}
            </li>
          )
        })}
      </ul>
    </>
  )
}
