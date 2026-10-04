import { Head, useForm } from "@inertiajs/react"
import { useId } from "react"
import { useTranslation } from "react-i18next"

import { SettingsSection } from "@/components/app/settings-section"
import { Button } from "@/components/ui/button"
import { Switch } from "@/components/ui/switch"
import { routes } from "@/generated/routes"
import type { SettingsEmailPreferencesEditProps } from "@/generated/pages"

/** Optional mail on or off; also the way back after a one-click unsubscribe. */
export default function EmailPreferencesEdit({ optionalEmails }: SettingsEmailPreferencesEditProps) {
  const { t } = useTranslation()
  const id = useId()
  const form = useForm({ optionalEmails })
  form.transform((data) => ({ user: data }))

  return (
    <SettingsSection title={t("settings.email_preferences.title")} description={t("settings.email_preferences.lead")}>
      <Head title={t("settings.email_preferences.title")} />
      <form
        className="grid gap-6"
        onSubmit={(event) => {
          event.preventDefault()
          form.patch(routes.settingsEmailPreference.update().url, { preserveScroll: true })
        }}
      >
        <label htmlFor={id} className="flex min-h-11 cursor-pointer items-start justify-between gap-4 rounded-lg border p-4">
          <span>
            <span className="block font-medium">{t("settings.email_preferences.optional_label")}</span>
            <span id={`${id}-help`} className="mt-1 block text-sm text-muted-foreground">
              {t("settings.email_preferences.optional_help")}
            </span>
          </span>
          <span className="flex shrink-0 items-center gap-2 pt-0.5 text-sm">
            {form.data.optionalEmails ? t("settings.email_preferences.on") : t("settings.email_preferences.off")}
            <Switch
              id={id}
              aria-describedby={`${id}-help`}
              checked={form.data.optionalEmails}
              onCheckedChange={(checked) => form.setData("optionalEmails", checked)}
            />
          </span>
        </label>
        <div className="rounded-lg bg-muted p-4">
          <p className="font-medium">{t("settings.email_preferences.always_title")}</p>
          <p className="mt-1 text-sm text-muted-foreground">{t("settings.email_preferences.always_body")}</p>
        </div>
        <div>
          <Button type="submit" disabled={form.processing || !form.isDirty}>
            {t("common.save_changes")}
          </Button>
        </div>
      </form>
    </SettingsSection>
  )
}
