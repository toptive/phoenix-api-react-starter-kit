import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { useNavigate } from "@tanstack/react-router"
import { useTranslation } from "react-i18next"
import { useApplyPasswordReset } from "@/api/hooks/auth"
import { useAppConfig } from "@/api/hooks/bootstrap"
import { AuthHeading } from "@/components/app/auth-card"
import { FormField } from "@/components/app/form-field"
import { FormError } from "@/components/app/form-error"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { passwordSchema } from "@/schemas/auth"
import { applyFormErrors, fieldMessage } from "@/lib/form-errors"
import { paths } from "@/lib/paths"
export default function ResetPasswordPage() {
  const { t } = useTranslation()
  const { auth } = useAppConfig()
  const changing = auth?.user.hasPassword
  const navigate = useNavigate()
  const form = useForm({
    resolver: zodResolver(passwordSchema),
    defaultValues: { password: "", passwordConfirmation: "" },
  })
  const reset = useApplyPasswordReset()
  return (
    <>
      <title>{t(changing ? "settings.password.title_change" : "settings.password.title_set")}</title>
      <AuthHeading
        title={t(changing ? "settings.password.title_change" : "settings.password.title_set")}
        description={t(changing ? "settings.password.lead_change" : "settings.password.lead_set")}
      />
      <form
        noValidate
        className="grid gap-5"
        onSubmit={form.handleSubmit(async (input) => {
          try {
            await reset.mutateAsync(input)
            void navigate({ to: paths.dashboard })
          } catch (error) {
            applyFormErrors(error, form.setError)
          }
        })}
      >
        <FormField
          label={t("fields.password")}
          help={t("settings.password.help")}
          error={fieldMessage(form.formState.errors.password?.message, 72)}
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
        <Button type="submit" size="lg" disabled={reset.isPending}>
          {t("settings.password.submit")}
        </Button>
      </form>
    </>
  )
}
