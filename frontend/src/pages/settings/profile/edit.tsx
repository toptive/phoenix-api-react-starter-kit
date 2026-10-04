import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { useTranslation } from "react-i18next"
import { toast } from "sonner"
import { useAppConfig } from "@/api/hooks/bootstrap"
import { useUpdateProfile } from "@/api/hooks/settings"
import { SettingsSection } from "@/components/app/settings-section"
import { FormField } from "@/components/app/form-field"
import { FormError } from "@/components/app/form-error"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { NativeSelect, NativeSelectOption } from "@/components/ui/native-select"
import { profileSchema } from "@/schemas/settings"
import { limits } from "@/schemas/limits"
import { applyFormErrors, fieldMessage } from "@/lib/form-errors"

export default function ProfileEdit() {
  const { t } = useTranslation()
  const { auth, locales } = useAppConfig()
  const update = useUpdateProfile()
  const form = useForm({
    resolver: zodResolver(profileSchema(locales)),
    defaultValues: { name: auth!.user.name, locale: auth!.user.locale },
  })
  return (
    <SettingsSection title={t("settings.profile.title")} description={t("settings.profile.lead")}>
      <title>{t("settings.profile.title")}</title>
      <form
        noValidate
        className="grid gap-6"
        onSubmit={form.handleSubmit(async (input) => {
          try {
            const user = await update.mutateAsync(input)
            form.reset({ name: user.name, locale: user.locale })
            toast.success(t("common.saved"))
          } catch (error) {
            applyFormErrors(error, form.setError)
          }
        })}
      >
        <FormField
          label={t("fields.name")}
          help={t("settings.profile.name_help")}
          error={fieldMessage(form.formState.errors.name?.message, { count: limits.nameMax })}
        >
          {(id, describedBy) => (
            <Input id={id} aria-describedby={describedBy} autoComplete="name" {...form.register("name")} />
          )}
        </FormField>
        <FormField
          label={t("fields.language")}
          help={t("settings.profile.language_help")}
          error={fieldMessage(form.formState.errors.locale?.message)}
        >
          {(id, describedBy) => (
            <NativeSelect id={id} aria-describedby={describedBy} className="min-h-11" {...form.register("locale")}>
              {locales.map((locale) => (
                <NativeSelectOption key={locale} value={locale}>
                  {t(`locale.name.${locale}`)}
                </NativeSelectOption>
              ))}
            </NativeSelect>
          )}
        </FormField>
        <FormError message={form.formState.errors.root?.message} />
        <div>
          <Button type="submit" disabled={update.isPending || !form.formState.isDirty}>
            {t("common.save_changes")}
          </Button>
        </div>
      </form>
    </SettingsSection>
  )
}
