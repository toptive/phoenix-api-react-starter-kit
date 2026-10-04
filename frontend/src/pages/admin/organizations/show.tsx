import { useParams } from "@tanstack/react-router"
import { useAdminOrganization } from "@/api/hooks/admin"
import { QueryState } from "@/components/app/query-state"
import { paths } from "@/lib/paths"
import { Link } from "@/components/app/link"
import { useTranslation } from "react-i18next"

import { DataTable } from "@/components/app/data-table"
import { PageHeader } from "@/components/app/page-header"

export default function AdminOrganizationShow() {
  const { t } = useTranslation()
  const { id = "" } = useParams({ strict: false }) as { id?: string }
  const query = useAdminOrganization(id)
  if (!query.data) return <QueryState pending={query.isPending} error={query.error} retry={query.refetch} />
  const { organization, memberships } = query.data

  return (
    <>
      <title>{organization.name}</title>
      <PageHeader title={organization.name} description={organization.slug} />
      <DataTable
        empty={<p>{t("admin.empty")}</p>}
        rows={memberships}
        rowKey={(m) => m.id}
        columns={[
          {
            header: t("fields.email"),
            cell: (m) =>
              m.user && (
                <Link
                  href={`${paths.adminUsers}/${m.user.id}`}
                  className="inline-flex min-h-11 items-center font-medium hover:underline"
                >
                  {m.user.email}
                </Link>
              ),
          },
          { header: t("admin.users.role"), cell: (m) => t(`level.${m.role}_${m.access}`) },
        ]}
      />
    </>
  )
}
