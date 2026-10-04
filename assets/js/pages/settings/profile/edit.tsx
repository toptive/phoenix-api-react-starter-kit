import { Head, useForm } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { FormField } from "@/components/app/form-field"
import { SettingsSection } from "@/components/app/settings-section"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NativeSelect, NativeSelectOption } from "@/components/ui/native-select"
import { routes } from "@/generated/routes"
import type { SettingsProfileEditProps } from "@/generated/pages"

export default function ProfileEdit({ auth, locales }: SettingsProfileEditProps) {
  const { t } = useTranslation()
  const form = useForm({ name: auth?.user.name ?? "", locale: auth?.user.locale ?? "en" })
  form.transform((data) => ({ user: data }))

  return (
    <SettingsSection title={t("settings.profile.title")} description={t("settings.profile.lead")}>
      <Head title={t("settings.profile.title")} />
      <form
        className="grid gap-6"
        onSubmit={(event) => {
          event.preventDefault()
          form.patch(routes.settingsProfile.update().url, { preserveScroll: true })
        }}
      >
        <FormField label={t("fields.name")} help={t("settings.profile.name_help")} error={form.errors.name}>
          {(id, describedBy) => <Input id={id} aria-describedby={describedBy} autoComplete="name" value={form.data.name} onChange={(e) => form.setData("name", e.target.value)} />}
        </FormField>
        <FormField label={t("fields.language")} help={t("settings.profile.language_help")} error={form.errors.locale}>
          {(id, describedBy) => (
            <NativeSelect id={id} aria-describedby={describedBy} value={form.data.locale} onChange={(e) => form.setData("locale", e.target.value)}>
              {locales.map((code) => (
                <NativeSelectOption key={code} value={code}>
                  {t(`locale.name.${code}`)}
                </NativeSelectOption>
              ))}
            </NativeSelect>
          )}
        </FormField>
        <div>
          <Button type="submit" disabled={form.processing || !form.isDirty}>
            {t("common.save_changes")}
          </Button>
        </div>
      </form>
    </SettingsSection>
  )
}
