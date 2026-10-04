import { limits } from "@/schemas/limits"
import { useState } from "react"
import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { useTranslation } from "react-i18next"
import { useAppConfig } from "@/api/hooks/bootstrap"
import { useChangeEmail } from "@/api/hooks/settings"
import { SettingsSection } from "@/components/app/settings-section"
import { FormField } from "@/components/app/form-field"
import { FormError } from "@/components/app/form-error"
import { AlertBanner } from "@/components/app/alert-banner"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { changeEmailSchema } from "@/schemas/settings"
import { applyFormErrors, fieldMessage } from "@/lib/form-errors"

export default function EmailEdit() {
  const { t } = useTranslation()
  const { auth, app } = useAppConfig()
  const change = useChangeEmail()
  const [sent, setSent] = useState<string | null>(null)
  const form = useForm({ resolver: zodResolver(changeEmailSchema), defaultValues: { email: "" } })
  return (
    <SettingsSection
      title={t("settings.email.title")}
      description={t("settings.email.lead", { email: auth?.user.email })}
    >
      <title>{t("settings.email.title")}</title>
      {sent ? (
        <AlertBanner tone="success" title={t("auth.check_email.title")}>
          {t("settings.email.check_email", { email: sent })}
        </AlertBanner>
      ) : !app.emailAvailable ? (
        <AlertBanner tone="warning" title={t("auth.unavailable.title")}>
          {t("errors.api.email_unavailable")}
        </AlertBanner>
      ) : (
        <form
          noValidate
          className="grid gap-6"
          onSubmit={form.handleSubmit(async (input) => {
            try {
              const result = await change.mutateAsync(input)
              setSent(result.email)
              form.reset()
            } catch (error) {
              applyFormErrors(error, form.setError)
            }
          })}
        >
          <FormField
            label={t("fields.new_email")}
            help={t("settings.email.help")}
            error={fieldMessage(form.formState.errors.email?.message, { count: limits.emailMax })}
          >
            {(id, describedBy) => (
              <Input
                id={id}
                type="email"
                aria-describedby={describedBy}
                autoComplete="email"
                {...form.register("email")}
              />
            )}
          </FormField>
          <FormError message={form.formState.errors.root?.message} />
          <div>
            <Button type="submit" disabled={change.isPending}>
              {t("settings.email.submit")}
            </Button>
          </div>
        </form>
      )}
      {sent && (
        <Button
          className="mt-6"
          variant="outline"
          onClick={() => {
            setSent(null)
            change.reset()
          }}
        >
          {t("settings.email.try_another")}
        </Button>
      )}
    </SettingsSection>
  )
}
