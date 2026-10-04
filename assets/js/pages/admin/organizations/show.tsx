import { Head, Link } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { DataTable } from "@/components/app/data-table"
import { PageHeader } from "@/components/app/page-header"
import { routes } from "@/generated/routes"
import type { AdminOrganizationsShowProps } from "@/generated/pages"


export default function AdminOrganizationShow({ organization, memberships }: AdminOrganizationsShowProps) {
  const { t } = useTranslation()

  return (
    <>
      <Head title={organization.name} />
      <PageHeader title={organization.name} description={organization.slug} />
      <DataTable
        rows={memberships}
        rowKey={(m) => m.id}
        columns={[
          {
            header: t("fields.email"),
            cell: (m) =>
              m.user && (
                <Link href={routes.adminUser.show(m.user.id).url} className="font-medium hover:underline">
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
