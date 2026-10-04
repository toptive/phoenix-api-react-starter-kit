import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { useTranslation } from "react-i18next"
import { toast } from "sonner"
import { useAppConfig } from "@/api/hooks/bootstrap"
import { useChangePassword } from "@/api/hooks/settings"
import { SettingsSection } from "@/components/app/settings-section"
import { FormField } from "@/components/app/form-field"
import { FormError } from "@/components/app/form-error"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { passwordSchema } from "@/schemas/settings"
import { limits } from "@/schemas/limits"
import { applyFormErrors, boundedFieldMessage, fieldMessage } from "@/lib/form-errors"

export default function PasswordEdit() {
  const { t } = useTranslation()
  const { auth } = useAppConfig()
  const change = useChangePassword()
  const form = useForm({
    resolver: zodResolver(passwordSchema),
    defaultValues: { password: "", passwordConfirmation: "" },
  })
  return (
    <SettingsSection
      title={t(auth?.user.hasPassword ? "settings.password.title_change" : "settings.password.title_set")}
      description={t(auth?.user.hasPassword ? "settings.password.lead_change" : "settings.password.lead_set")}
    >
      <title>{t("settings.password.nav")}</title>
      <form
        noValidate
        className="grid gap-6"
        onSubmit={form.handleSubmit(async (input) => {
          try {
            await change.mutateAsync(input)
            toast.success(t("settings.password.saved"))
          } catch (error) {
            applyFormErrors(error, form.setError)
          } finally {
            form.setValue("password", "")
            form.setValue("passwordConfirmation", "")
          }
        })}
      >
        <FormField
          label={t("fields.new_password")}
          help={t("settings.password.help")}
          error={boundedFieldMessage(
            form.formState.errors.password?.message,
            limits.passwordMin,
            limits.passwordMaxBytes,
          )}
        >
          {(id, describedBy) => (
            <Input
              id={id}
              aria-describedby={describedBy}
              type="password"
              autoComplete="new-password"
              {...form.register("password")}
            />
          )}
        </FormField>
        <FormField
          label={t("fields.password_confirmation")}
          error={fieldMessage(form.formState.errors.passwordConfirmation?.message)}
        >
          {(id, describedBy) => (
            <Input
              id={id}
              aria-describedby={describedBy}
              type="password"
              autoComplete="new-password"
              {...form.register("passwordConfirmation")}
            />
          )}
        </FormField>
        <FormError message={form.formState.errors.root?.message} />
        <div>
          <Button type="submit" disabled={change.isPending}>
            {t("settings.password.submit")}
          </Button>
        </div>
      </form>
    </SettingsSection>
  )
}
