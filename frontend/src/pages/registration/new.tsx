import { useCallback, useState } from "react"
import { useNavigate, useSearch } from "@tanstack/react-router"
import { Trans, useTranslation } from "react-i18next"
import { useForm, useWatch } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { useAppConfig } from "@/api/hooks/bootstrap"
import { useRegister } from "@/api/hooks/auth"
import { AuthHeading } from "@/components/app/auth-card"
import { AlertBanner } from "@/components/app/alert-banner"
import { FormField } from "@/components/app/form-field"
import { FormError } from "@/components/app/form-error"
import { FormStepper } from "@/components/app/form-stepper"
import { Link } from "@/components/app/link"
import { TextLink } from "@/components/app/text-link"
import { Turnstile } from "@/components/app/turnstile"
import { Input } from "@/components/ui/input"
import { Checkbox } from "@/components/ui/checkbox"
import { Label } from "@/components/ui/label"
import { registrationSchema } from "@/schemas/auth"
import { limits } from "@/schemas/limits"
import { applyFormErrors, fieldMessage } from "@/lib/form-errors"
import { ApiError } from "@/api/http"
import { paths } from "@/lib/paths"

export default function RegisterPage() {
  const { t, i18n } = useTranslation()
  const navigate = useNavigate()
  const { app, turnstile } = useAppConfig()
  const search = useSearch({ strict: false }) as { email?: string }
  const form = useForm({
    resolver: zodResolver(registrationSchema),
    defaultValues: { name: "", email: search.email ?? "", termsAccepted: false, turnstileToken: "" },
  })
  const values = useWatch({ control: form.control })
  const register = useRegister()
  const [attempt, setAttempt] = useState(0)
  const [step, setStep] = useState(0)
  const { setValue } = form
  const onToken = useCallback((token: string) => setValue("turnstileToken", token), [setValue])
  const closed = app.signupMode === "closed"
  if (closed || !app.emailAvailable)
    return (
      <>
        <AuthHeading title={t("auth.registration.title")} />
        <AlertBanner tone="warning" title={t(closed ? "auth.registration.closed_title" : "auth.unavailable.title")}>
          {t(closed ? "auth.registration.closed_body" : "auth.unavailable.registration_body")}
        </AlertBanner>
        <TextLink href={paths.signIn}>{t("nav.sign_in")}</TextLink>
      </>
    )
  const submit = form.handleSubmit(
    async (input) => {
      try {
        const result = await register.mutateAsync({ ...input, locale: i18n.language })
        void navigate({ to: paths.signIn, search: { email: result.email, newAccount: "1" } })
      } catch (error) {
        applyFormErrors(error, form.setError)
        if (error instanceof ApiError && error.code === "validation_failed")
          setStep("name" in error.details ? 0 : "email" in error.details ? 1 : 2)
      } finally {
        setAttempt((value) => value + 1)
        setValue("turnstileToken", "")
      }
    },
    (errors) => setStep(errors.name ? 0 : errors.email ? 1 : 2),
  )
  return (
    <>
      <title>{t("auth.registration.title")}</title>
      <AuthHeading title={t("auth.registration.title")} description={t("auth.registration.lead")} />
      {app.signupMode === "invite" && (
        <AlertBanner tone="info" title={t("auth.registration.invite_title")} className="mb-6">
          {t("auth.registration.invite_body")}
        </AlertBanner>
      )}
      <FormStepper
        stepIndex={step}
        onStepChange={setStep}
        reviewLastStep
        processing={register.isPending}
        submitLabel={t("auth.registration.submit")}
        onSubmit={() => {
          void submit()
        }}
        steps={[
          {
            title: t("fields.name"),
            isValid: () => registrationSchema.shape.name.safeParse(form.getValues("name")).success,
            content: (
              <FormField
                label={t("fields.name")}
                error={fieldMessage(form.formState.errors.name?.message, { count: limits.nameMax })}
              >
                {(id, describedBy) => (
                  <Input id={id} aria-describedby={describedBy} autoComplete="name" {...form.register("name")} />
                )}
              </FormField>
            ),
          },
          {
            title: t("fields.email"),
            isValid: () => registrationSchema.shape.email.safeParse(form.getValues("email")).success,
            content: (
              <FormField
                label={t("fields.email")}
                help={t("auth.registration.email_help")}
                error={fieldMessage(form.formState.errors.email?.message, { count: limits.emailMax })}
              >
                {(id, describedBy) => (
                  <Input
                    id={id}
                    aria-describedby={describedBy}
                    type="email"
                    autoComplete="email"
                    {...form.register("email")}
                  />
                )}
              </FormField>
            ),
          },
          {
            title: t("auth.registration.consent_title"),
            isValid: () => form.getValues("termsAccepted"),
            content: (
              <>
                <div className="flex items-start gap-3">
                  <Checkbox
                    id="terms-accepted"
                    checked={values.termsAccepted}
                    onCheckedChange={(checked) => setValue("termsAccepted", checked === true)}
                    aria-describedby="terms-error"
                  />
                  <Label htmlFor="terms-accepted" className="leading-relaxed font-normal">
                    <Trans
                      i18nKey="auth.registration.accept"
                      components={{
                        terms: <Link href={paths.legal("terms", i18n.language)} className="underline" />,
                        privacy: <Link href={paths.legal("privacy", i18n.language)} className="underline" />,
                      }}
                    />
                  </Label>
                </div>
                <div id="terms-error">
                  <FormError message={fieldMessage(form.formState.errors.termsAccepted?.message)} />
                </div>
              </>
            ),
          },
          {
            title: t("stepper.review"),
            isValid: () => !turnstile.required || Boolean(form.getValues("turnstileToken")),
            content: (
              <>
                <dl className="grid gap-3">
                  <div>
                    <dt className="text-sm text-muted-foreground">{t("fields.name")}</dt>
                    <dd>{values.name}</dd>
                  </div>
                  <div>
                    <dt className="text-sm text-muted-foreground">{t("fields.email")}</dt>
                    <dd>{values.email}</dd>
                  </div>
                </dl>
                <Turnstile
                  action="registration"
                  attempt={attempt}
                  onToken={onToken}
                  error={fieldMessage(form.formState.errors.turnstileToken?.message)}
                />
              </>
            ),
          },
        ]}
      />
      <FormError message={form.formState.errors.root?.message} />
      <p className="mt-8 text-sm text-muted-foreground">
        {t("auth.registration.have_account")} <TextLink href={paths.signIn}>{t("nav.sign_in")}</TextLink>
      </p>
    </>
  )
}
