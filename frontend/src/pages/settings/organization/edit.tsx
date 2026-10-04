import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { useTranslation } from "react-i18next"
import { toast } from "sonner"
import { useOrganizationSettings, useUpdateOrganization } from "@/api/hooks/people"
import { SettingsSection } from "@/components/app/settings-section"
import { QueryState } from "@/components/app/query-state"
import { FormField } from "@/components/app/form-field"
import { FormError } from "@/components/app/form-error"
import { AlertBanner } from "@/components/app/alert-banner"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { organizationSchema } from "@/schemas/organizations"
import { limits } from "@/schemas/limits"
import type { OrganizationSettings } from "@/api/generated/serializers"
import { applyFormErrors, boundedFieldMessage } from "@/lib/form-errors"

export default function OrganizationEdit() {
  const { t } = useTranslation()
  const query = useOrganizationSettings()
  return (
    <SettingsSection title={t("settings.organization.title")} description={t("settings.organization.lead")}>
      <title>{t("settings.organization.title")}</title>
      <QueryState pending={query.isPending} error={query.error} retry={query.refetch} />
      {query.data && <OrganizationForm key={query.data.organization.id} {...query.data} />}
    </SettingsSection>
  )
}
function OrganizationForm({ organization, canEdit }: OrganizationSettings) {
  const { t } = useTranslation()
  const update = useUpdateOrganization()
  const form = useForm({ resolver: zodResolver(organizationSchema), defaultValues: { name: organization.name } })
  return (
    <>
      {!canEdit && (
        <AlertBanner className="mb-6" title={t("settings.organization.read_only")}>
          {t("settings.organization.read_only_help")}
        </AlertBanner>
      )}
      <form
        noValidate
        className="grid gap-6"
        onSubmit={form.handleSubmit(async (input) => {
          try {
            const result = await update.mutateAsync(input)
            form.reset({ name: result.name })
            toast.success(t("common.saved"))
          } catch (error) {
            applyFormErrors(error, form.setError)
          }
        })}
      >
        <FormField
          label={t("fields.organization_name")}
          help={t("settings.organization.name_help")}
          error={boundedFieldMessage(
            form.formState.errors.name?.message,
            limits.organizationMin,
            limits.organizationMax,
          )}
        >
          {(id, describedBy) => (
            <Input id={id} aria-describedby={describedBy} disabled={!canEdit} {...form.register("name")} />
          )}
        </FormField>
        <FormError message={form.formState.errors.root?.message} />
        {canEdit && (
          <div>
            <Button type="submit" disabled={update.isPending || !form.formState.isDirty}>
              {t("common.save_changes")}
            </Button>
          </div>
        )}
      </form>
    </>
  )
}
