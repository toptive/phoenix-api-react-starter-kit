import { Head, Link, router, useForm } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { FormField } from "@/components/app/form-field"
import { PageHeader } from "@/components/app/page-header"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NativeSelect, NativeSelectOption } from "@/components/ui/native-select"
import { routes } from "@/generated/routes"
import type { AdminUsersShowProps } from "@/generated/pages"


export default function AdminUserShow({ user, organizations, roles, auth }: AdminUsersShowProps) {
  const { t } = useTranslation()
  const impersonation = useForm({ reason: "" })
  impersonation.transform((data) => ({ impersonation: data }))
  const canImpersonate = user.role !== "superadmin" && user.id !== auth?.user.id

  return (
    <>
      <Head title={user.email} />
      <PageHeader title={user.name || user.email} description={user.email} />

      <div className="grid gap-10 lg:grid-cols-2">
        <section className="space-y-4">
          <h2 className="text-lg font-semibold">{t("admin.users.role")}</h2>
          <NativeSelect
            aria-label={t("admin.users.role")}
            value={user.role}
            disabled={user.id === auth?.user.id}
            onChange={(e) => router.patch(routes.adminUser.update(user.id).url, { user: { role: e.target.value } }, { preserveScroll: true })}
          >
            {roles.map((role) => (
              <NativeSelectOption key={role} value={role}>
                {t(`global_roles.${role}`)}
              </NativeSelectOption>
            ))}
          </NativeSelect>

          <h2 className="pt-6 text-lg font-semibold">{t("admin.users.organizations")}</h2>
          <ul className="divide-y rounded-xl border bg-card">
            {organizations.map((organization) => (
              <li key={organization.id} className="p-3">
                <Link href={routes.adminOrganization.show(organization.id).url} className="hover:underline">
                  {organization.name}
                </Link>
              </li>
            ))}
          </ul>
        </section>

        {canImpersonate && (
          <section className="space-y-4 rounded-xl border bg-card p-5">
            <h2 className="text-lg font-semibold">{t("admin.users.impersonate_title")}</h2>
            <p className="text-sm text-muted-foreground">{t("admin.users.impersonate_lead")}</p>
            <form
              className="grid gap-4"
              onSubmit={(event) => {
                event.preventDefault()
                impersonation.post(routes.adminUserImpersonation.create(user.id).url)
              }}
            >
              <FormField label={t("admin.users.reason")} help={t("admin.users.reason_help")} error={impersonation.errors.reason}>
                {(id, describedBy) => <Input id={id} aria-describedby={describedBy} value={impersonation.data.reason} onChange={(e) => impersonation.setData("reason", e.target.value)} />}
              </FormField>
              <div>
                <Button type="submit" variant="outline" disabled={impersonation.processing}>
                  {t("admin.users.impersonate", { email: user.email })}
                </Button>
              </div>
            </form>
          </section>
        )}
      </div>
    </>
  )
}
