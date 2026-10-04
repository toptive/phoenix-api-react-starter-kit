import { useState } from "react"
import { useParams, useNavigate } from "@tanstack/react-router"
import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { useTranslation } from "react-i18next"
import { toast } from "sonner"
import { useAdminUser, useUpdateAdminUser, useImpersonate } from "@/api/hooks/admin"
import { useAppConfig } from "@/api/hooks/bootstrap"
import type { User } from "@/api/generated/serializers"
import { impersonationSchema } from "@/schemas/admin"
import { applyFormErrors, boundedFieldMessage } from "@/lib/form-errors"
import { paths } from "@/lib/paths"
import { Link } from "@/components/app/link"
import { FormField } from "@/components/app/form-field"
import { FormError } from "@/components/app/form-error"
import { QueryState } from "@/components/app/query-state"
import { PageHeader } from "@/components/app/page-header"
import { ConfirmDialog } from "@/components/app/confirm-dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NativeSelect, NativeSelectOption } from "@/components/ui/native-select"

const roles: User["role"][] = ["user", "superadmin"]
export default function AdminUserShow() {
  const { id = "" } = useParams({ strict: false }) as { id?: string }
  const query = useAdminUser(id)
  if (!query.data) return <QueryState pending={query.isPending} error={query.error} retry={query.refetch} />
  return (
    <UserDetail key={`${id}:${query.data.user.role}`} user={query.data.user} organizations={query.data.organizations} />
  )
}
function UserDetail({ user, organizations }: NonNullable<ReturnType<typeof useAdminUser>["data"]>) {
  const { t } = useTranslation()
  const { auth } = useAppConfig()
  const navigate = useNavigate()
  const update = useUpdateAdminUser(user.id)
  const impersonate = useImpersonate(user.id)
  const [role, setRole] = useState(user.role)
  const form = useForm({ resolver: zodResolver(impersonationSchema), defaultValues: { reason: "" } })
  return (
    <>
      <title>{user.email}</title>
      <PageHeader title={user.name || user.email} description={user.email} />
      <div className="grid gap-10 lg:grid-cols-2">
        <section className="space-y-4">
          <h2 className="text-lg font-semibold">{t("admin.users.role")}</h2>
          <NativeSelect
            className="min-h-11"
            aria-label={t("admin.users.role")}
            value={role}
            disabled={user.id === auth?.user.id || update.isPending}
            onChange={(event) => setRole(event.target.value as User["role"])}
          >
            {roles.map((value) => (
              <NativeSelectOption key={value} value={value}>
                {t(`global_roles.${value}`)}
              </NativeSelectOption>
            ))}
          </NativeSelect>
          <ConfirmDialog
            destructive={false}
            trigger={<Button disabled={role === user.role || update.isPending}>{t("common.save_changes")}</Button>}
            title={t("admin.users.role_confirm_title")}
            description={t("admin.users.role_confirm_body", { email: user.email, role: t(`global_roles.${role}`) })}
            confirmLabel={t("common.save_changes")}
            onConfirm={() => update.mutate(role, { onSuccess: () => toast.success(t("flash.admin.user_updated")) })}
          />
          <FormError error={update.error} />
          <h2 className="pt-6 text-lg font-semibold">{t("admin.users.organizations")}</h2>
          {organizations.length ? (
            <ul className="divide-y rounded-xl border bg-card">
              {organizations.map((org) => (
                <li key={org.id} className="p-3">
                  <Link
                    className="flex min-h-11 items-center hover:underline"
                    href={`${paths.adminOrganizations}/${org.id}`}
                  >
                    {org.name}
                  </Link>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-muted-foreground">{t("admin.empty")}</p>
          )}
        </section>
        {user.role !== "superadmin" && user.id !== auth?.user.id && (
          <section className="space-y-4 rounded-xl border bg-card p-5">
            <h2 className="text-lg font-semibold">{t("admin.users.impersonate_title")}</h2>
            <p className="text-sm text-muted-foreground">{t("admin.users.impersonate_lead")}</p>
            <form
              noValidate
              className="grid gap-4"
              onSubmit={form.handleSubmit(async (input) => {
                try {
                  await impersonate.mutateAsync(input)
                  await navigate({ to: paths.dashboard })
                } catch (error) {
                  applyFormErrors(error, form.setError)
                }
              })}
            >
              <FormField
                label={t("admin.users.reason")}
                help={t("admin.users.reason_help")}
                error={boundedFieldMessage(form.formState.errors.reason?.message, 5, 255)}
              >
                {(id, describedBy) => <Input id={id} aria-describedby={describedBy} {...form.register("reason")} />}
              </FormField>
              <FormError message={form.formState.errors.root?.message} />
              <Button type="submit" variant="outline" disabled={impersonate.isPending}>
                {t("admin.users.impersonate", { email: user.email })}
              </Button>
            </form>
          </section>
        )}
      </div>
    </>
  )
}
