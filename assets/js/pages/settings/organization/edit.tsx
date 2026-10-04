import { Head, useForm } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { AlertBanner } from "@/components/app/alert-banner"
import { FormField } from "@/components/app/form-field"
import { SettingsSection } from "@/components/app/settings-section"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { routes } from "@/generated/routes"
import type { SettingsOrganizationEditProps } from "@/generated/pages"

export default function OrganizationEdit({ auth, canEdit }: SettingsOrganizationEditProps) {
  const { t } = useTranslation()
  const form = useForm({ name: auth?.organization.name ?? "" })
  form.transform((data) => ({ organization: data }))

  return (
    <SettingsSection title={t("settings.organization.title")} description={t("settings.organization.lead")}>
      <Head title={t("settings.organization.title")} />
      {!canEdit && (
        <AlertBanner className="mb-6" title={t("settings.organization.read_only")}>
          {t("settings.organization.read_only_help")}
        </AlertBanner>
      )}
      <form
        className="grid gap-6"
        onSubmit={(event) => {
          event.preventDefault()
          form.patch(routes.settingsOrganization.update().url, { preserveScroll: true })
        }}
      >
        <FormField label={t("fields.organization_name")} help={t("settings.organization.name_help")} error={form.errors.name}>
          {(id, describedBy) => <Input id={id} aria-describedby={describedBy} disabled={!canEdit} value={form.data.name} onChange={(e) => form.setData("name", e.target.value)} />}
        </FormField>
        {canEdit && (
          <div>
            <Button type="submit" disabled={form.processing || !form.isDirty}>
              {t("common.save_changes")}
            </Button>
          </div>
        )}
      </form>
    </SettingsSection>
  )
}
