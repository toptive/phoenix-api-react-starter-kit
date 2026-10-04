import { Head, useForm } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { FormField } from "@/components/app/form-field"
import { SettingsSection } from "@/components/app/settings-section"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { routes } from "@/generated/routes"
import type { SettingsPasswordEditProps } from "@/generated/pages"

export default function PasswordEdit({ auth }: SettingsPasswordEditProps) {
  const { t } = useTranslation()
  const form = useForm({ password: "", passwordConfirmation: "" })
  form.transform((data) => ({ user: data }))
  const hasPassword = auth?.user.hasPassword ?? false

  return (
    <SettingsSection
      title={hasPassword ? t("settings.password.title_change") : t("settings.password.title_set")}
      description={hasPassword ? t("settings.password.lead_change") : t("settings.password.lead_set")}
    >
      <Head title={t("settings.password.nav")} />
      <form
        className="grid gap-6"
        onSubmit={(event) => {
          event.preventDefault()
          form.patch(routes.settingsPassword.update().url, { onFinish: () => form.reset() })
        }}
      >
        <FormField label={t("fields.new_password")} help={t("settings.password.help")} error={form.errors.password}>
          {(id, describedBy) => (
            <Input id={id} type="password" autoComplete="new-password" aria-describedby={describedBy} value={form.data.password} onChange={(e) => form.setData("password", e.target.value)} />
          )}
        </FormField>
        <FormField label={t("fields.password_confirmation")} error={form.errors.passwordConfirmation}>
          {(id, describedBy) => (
            <Input id={id} type="password" autoComplete="new-password" aria-describedby={describedBy} value={form.data.passwordConfirmation} onChange={(e) => form.setData("passwordConfirmation", e.target.value)} />
          )}
        </FormField>
        <div>
          <Button type="submit" disabled={form.processing}>
            {t("settings.password.submit")}
          </Button>
        </div>
      </form>
    </SettingsSection>
  )
}
