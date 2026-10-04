import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { useNavigate } from "@tanstack/react-router"
import { useTranslation } from "react-i18next"
import { googleStartUrl, useSudo } from "@/api/hooks/auth"
import { useAppConfig } from "@/api/hooks/bootstrap"
import { AuthHeading } from "@/components/app/auth-card"
import { FormField } from "@/components/app/form-field"
import { FormError } from "@/components/app/form-error"
import { MagicLinkForm } from "@/components/app/magic-link-form"
import { Input } from "@/components/ui/input"
import { AlertBanner } from "@/components/app/alert-banner"
import { returnPath } from "@/lib/auth-flow"
import { Button, buttonVariants } from "@/components/ui/button"
import { sudoSchema } from "@/schemas/auth"
import { applyFormErrors, fieldMessage } from "@/lib/form-errors"
import { destinationAfterAuth } from "@/lib/auth-flow"
export default function SudoPage() {
  const { t } = useTranslation()
  const { auth, app } = useAppConfig()
  const navigate = useNavigate()
  const form = useForm({ resolver: zodResolver(sudoSchema), defaultValues: { password: "" } })
  const sudo = useSudo()
  return (
    <>
      <title>{t("auth.session.reauth_title")}</title>
      <AuthHeading title={t("auth.session.reauth_title")} description={t("auth.session.reauth_lead")} />
      {auth?.user.hasPassword && (
        <form
          noValidate
          className="mb-6 grid gap-5"
          onSubmit={form.handleSubmit(async (input) => {
            try {
              await sudo.mutateAsync(input)
              void navigate({ to: destinationAfterAuth() })
            } catch (error) {
              applyFormErrors(error, form.setError)
            } finally {
              form.resetField("password")
            }
          })}
        >
          <FormField label={t("fields.password")} error={fieldMessage(form.formState.errors.password?.message)}>
            {(id, describedBy) => (
              <Input
                id={id}
                aria-describedby={describedBy}
                type="password"
                autoComplete="current-password"
                {...form.register("password")}
              />
            )}
          </FormField>
          <FormError message={form.formState.errors.root?.message} />
          <Button type="submit" size="lg" disabled={sudo.isPending}>
            {t("auth.session.submit")}
          </Button>
        </form>
      )}
      {app.emailAvailable && <MagicLinkForm email={auth?.user.email} />}
      {app.googleEnabled && (
        <a
          href={googleStartUrl(returnPath.get() ?? undefined)}
          className={buttonVariants({ variant: "outline", size: "lg", className: "mt-6 w-full" })}
        >
          {t("auth.session.google")}
        </a>
      )}
      {!auth?.user.hasPassword && !app.emailAvailable && !app.googleEnabled && (
        <AlertBanner tone="warning" title={t("auth.unavailable.title")}>
          {t("auth.unavailable.session_body")}
        </AlertBanner>
      )}
    </>
  )
}
