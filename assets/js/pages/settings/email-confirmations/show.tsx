import { Head, useForm } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { SettingsSection } from "@/components/app/settings-section"
import { Button } from "@/components/ui/button"
import { routes } from "@/generated/routes"
import type { SettingsEmailConfirmationsShowProps } from "@/generated/pages"

/** A button, not an automatic change: email scanners that open links cannot use the token. */
export default function EmailConfirmationShow({ token, email }: SettingsEmailConfirmationsShowProps) {
  const { t } = useTranslation()
  const form = useForm({ token })

  return (
    <SettingsSection title={t("settings.email_confirmation.title")} description={t("settings.email_confirmation.lead", { email })}>
      <Head title={t("settings.email_confirmation.title")} />
      <form
        onSubmit={(event) => {
          event.preventDefault()
          form.post(routes.settingsEmailConfirmation.create().url)
        }}
      >
        <Button type="submit" size="lg" disabled={form.processing}>
          {t("settings.email_confirmation.submit")}
        </Button>
      </form>
    </SettingsSection>
  )
}
