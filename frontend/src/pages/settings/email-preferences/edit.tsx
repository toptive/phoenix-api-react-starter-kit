import { useId } from "react"
import { useForm, useWatch } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { useTranslation } from "react-i18next"
import { toast } from "sonner"
import { useEmailPreferences, useUpdateEmailPreferences } from "@/api/hooks/settings"
import { SettingsSection } from "@/components/app/settings-section"
import { QueryState } from "@/components/app/query-state"
import { FormError } from "@/components/app/form-error"
import { Switch } from "@/components/ui/switch"
import { Button } from "@/components/ui/button"
import { emailPreferencesSchema } from "@/schemas/settings"
import { applyFormErrors, fieldMessage } from "@/lib/form-errors"

export default function EmailPreferencesEdit() {
  const { t } = useTranslation()
  const query = useEmailPreferences()
  return (
    <SettingsSection title={t("settings.email_preferences.title")} description={t("settings.email_preferences.lead")}>
      <title>{t("settings.email_preferences.title")}</title>
      <QueryState pending={query.isPending} error={query.error} retry={query.refetch} />
      {query.data && <PreferencesForm optionalEmails={query.data.optionalEmails} />}
    </SettingsSection>
  )
}
function PreferencesForm({ optionalEmails }: { optionalEmails: boolean }) {
  const { t } = useTranslation()
  const id = useId()
  const update = useUpdateEmailPreferences()
  const form = useForm({ resolver: zodResolver(emailPreferencesSchema), defaultValues: { optionalEmails } })
  const checked = useWatch({ control: form.control, name: "optionalEmails" })
  return (
    <form
      noValidate
      className="grid gap-6"
      onSubmit={form.handleSubmit(async (input) => {
        try {
          const result = await update.mutateAsync(input)
          form.reset(result)
          toast.success(t("common.saved"))
        } catch (error) {
          applyFormErrors(error, form.setError)
        }
      })}
    >
      <label
        htmlFor={id}
        className="flex min-h-11 cursor-pointer items-start justify-between gap-4 rounded-lg border p-4"
      >
        <span>
          <span className="block font-medium">{t("settings.email_preferences.optional_label")}</span>
          <span id={`${id}-help`} className="mt-1 block text-sm text-muted-foreground">
            {t("settings.email_preferences.optional_help")}
          </span>
        </span>
        <span className="flex shrink-0 items-center gap-2 pt-0.5 text-sm">
          {t(checked ? "settings.email_preferences.on" : "settings.email_preferences.off")}
          <Switch
            id={id}
            aria-describedby={`${id}-help`}
            checked={checked}
            onCheckedChange={(value) => form.setValue("optionalEmails", value, { shouldDirty: true })}
          />
        </span>
      </label>
      <FormError message={fieldMessage(form.formState.errors.optionalEmails?.message)} />
      <div className="rounded-lg bg-muted p-4">
        <p className="font-medium">{t("settings.email_preferences.always_title")}</p>
        <p className="mt-1 text-sm text-muted-foreground">{t("settings.email_preferences.always_body")}</p>
      </div>
      <FormError message={form.formState.errors.root?.message} />
      <div>
        <Button type="submit" disabled={update.isPending || !form.formState.isDirty}>
          {t("common.save_changes")}
        </Button>
      </div>
    </form>
  )
}
