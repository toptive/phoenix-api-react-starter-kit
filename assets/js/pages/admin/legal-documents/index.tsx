import { Head, Link } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { PageHeader } from "@/components/app/page-header"
import { StatusBadge } from "@/components/app/status-badge"
import { routes } from "@/generated/routes"
import type { AdminLegalDocumentsIndexProps } from "@/generated/pages"

export default function AdminLegalIndex({ documents }: AdminLegalDocumentsIndexProps) {
  const { t } = useTranslation()

  return (
    <>
      <Head title={t("admin.legal.title")} />
      <PageHeader title={t("admin.legal.title")} description={t("admin.legal.lead")} />
      <ul className="divide-y rounded-xl border bg-card">
        {documents.map((doc) => {
          const published = doc.versions.find((v) => v.id === doc.publishedVersionId)
          return (
            <li key={doc.id} className="flex items-center gap-4 p-4">
              <Link href={routes.adminLegalDocument.show(doc.slug).url} className="flex-1 font-medium hover:underline">
                {t(`legal.${doc.slug}`)}
              </Link>
              {published ? (
                <StatusBadge tone="success">{t("admin.legal.published_version", { version: published.number })}</StatusBadge>
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
