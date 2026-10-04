import { Head, useForm } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { FormField } from "@/components/app/form-field"
import { SettingsSection } from "@/components/app/settings-section"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { routes } from "@/generated/routes"
import type { SettingsEmailEditProps } from "@/generated/pages"

export default function EmailEdit({ auth }: SettingsEmailEditProps) {
  const { t } = useTranslation()
  const form = useForm({ email: "" })
  form.transform((data) => ({ user: data }))

  return (
    <SettingsSection title={t("settings.email.title")} description={t("settings.email.lead", { email: auth?.user.email })}>
      <Head title={t("settings.email.title")} />
      <form
        className="grid gap-6"
        onSubmit={(event) => {
          event.preventDefault()
          form.patch(routes.settingsEmail.update().url, { onSuccess: () => form.reset() })
        }}
      >
        <FormField label={t("fields.new_email")} help={t("settings.email.help")} error={form.errors.email}>
          {(id, describedBy) => <Input id={id} type="email" autoComplete="email" aria-describedby={describedBy} value={form.data.email} onChange={(e) => form.setData("email", e.target.value)} />}
        </FormField>
        <div>
          <Button type="submit" disabled={form.processing || form.data.email === ""}>
            {t("settings.email.submit")}
          </Button>
        </div>
      </form>
    </SettingsSection>
  )
}
