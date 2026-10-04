import { useNavigate } from "@tanstack/react-router"
import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { useTranslation } from "react-i18next"
import { useCreateOrganization } from "@/api/hooks/organizations"
import { PageHeader } from "@/components/app/page-header"
import { FormField } from "@/components/app/form-field"
import { FormError } from "@/components/app/form-error"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { organizationSchema } from "@/schemas/organizations"
import { limits } from "@/schemas/limits"
import { applyFormErrors, boundedFieldMessage } from "@/lib/form-errors"
import { paths } from "@/lib/paths"

export default function OrganizationNew() {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const create = useCreateOrganization()
  const form = useForm({ resolver: zodResolver(organizationSchema), defaultValues: { name: "" } })
  return (
    <div className="max-w-xl">
      <title>{t("organizations.new.title")}</title>
      <PageHeader title={t("organizations.new.title")} description={t("organizations.new.lead")} />
      <form
        noValidate
        className="grid gap-5"
        onSubmit={form.handleSubmit(async (input) => {
          try {
            await create.mutateAsync(input)
            void navigate({ to: paths.dashboard })
          } catch (error) {
            applyFormErrors(error, form.setError)
          }
        })}
      >
        <FormField
          label={t("fields.organization_name")}
          help={t("organizations.new.name_help")}
          error={boundedFieldMessage(
            form.formState.errors.name?.message,
            limits.organizationMin,
            limits.organizationMax,
          )}
        >
          {(id, describedBy) => (
            <Input id={id} aria-describedby={describedBy} autoComplete="organization" {...form.register("name")} />
          )}
        </FormField>
        <FormError message={form.formState.errors.root?.message} />
        <div>
          <Button type="submit" disabled={create.isPending}>
            {t("organizations.new.submit")}
          </Button>
        </div>
      </form>
    </div>
  )
}
