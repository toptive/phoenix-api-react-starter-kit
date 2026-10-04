import { Head, Link, useForm } from "@inertiajs/react"
import { useCallback, useState } from "react"
import { Trans, useTranslation } from "react-i18next"

import { AlertBanner } from "@/components/app/alert-banner"
import { AuthHeading } from "@/components/app/auth-card"
import { FormField } from "@/components/app/form-field"
import { TextLink } from "@/components/app/text-link"
import { Turnstile } from "@/components/app/turnstile"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { routes } from "@/generated/routes"
import { usePublicRoutes } from "@/hooks/use-public-routes"
import { useSharedProps } from "@/hooks/use-shared-props"
import type { RegistrationNewProps } from "@/generated/pages"

export default function RegistrationNew({ email, emailAvailable, signupMode }: RegistrationNewProps) {
  const { t } = useTranslation()
  const form = useForm({ name: "", email, termsAccepted: false, turnstileToken: "" })
  const { setData } = form
  const { turnstile } = useSharedProps()
  // A Turnstile token works once: every submit asks the widget for a new one.
  const [attempt, setAttempt] = useState(0)
  const onToken = useCallback((token: string) => setData("turnstileToken", token), [setData])
  const publicRoutes = usePublicRoutes()
  const legalLink = "underline underline-offset-4"

  form.transform((data) => ({ user: data }))

  // Sign-up closed (SIGNUP_MODE=closed), or no mail to confirm an account: say so instead
  // of a form that can only fail.
  if (signupMode === "closed" || !emailAvailable) {
    const closed = signupMode === "closed"

    return (
      <>
        <Head title={t("auth.registration.title")} />
        <AuthHeading title={t("auth.registration.title")} />
        <AlertBanner tone="warning" title={closed ? t("auth.registration.closed_title") : t("auth.unavailable.title")}>
          {closed ? t("auth.registration.closed_body") : t("auth.unavailable.registration_body")}
        </AlertBanner>
        <p className="mt-8 text-sm text-muted-foreground">
          {t("auth.registration.have_account")} <TextLink href={routes.session.new().url}>{t("nav.sign_in")}</TextLink>
        </p>
      </>
    )
  }

  return (
    <>
      <Head title={t("auth.registration.title")} />
      <AuthHeading title={t("auth.registration.title")} description={t("auth.registration.lead")} />
      {signupMode === "invite" && (
        <AlertBanner tone="info" title={t("auth.registration.invite_title")} className="mb-6">
          {t("auth.registration.invite_body")}
        </AlertBanner>
      )}
      <form
        className="grid gap-5"
        onSubmit={(event) => {
          event.preventDefault()
          form.post(routes.registration.create().url, { onFinish: () => setAttempt((value) => value + 1) })
        }}
      >
        <FormField label={t("fields.name")} error={form.errors.name}>
          {(id, describedBy) => (
            <Input id={id} aria-describedby={describedBy} autoComplete="name" required value={form.data.name} onChange={(e) => form.setData("name", e.target.value)} />
          )}
        </FormField>
        <FormField label={t("fields.email")} help={t("auth.registration.email_help")} error={form.errors.email}>
          {(id, describedBy) => (
            <Input id={id} type="email" aria-describedby={describedBy} autoComplete="email" required value={form.data.email} onChange={(e) => form.setData("email", e.target.value)} />
          )}
        </FormField>
        <div className="grid gap-2">
          <div className="flex items-start gap-3">
            <Checkbox
              id="terms-accepted"
              required
              className="mt-0.5"
              aria-invalid={form.errors.termsAccepted ? true : undefined}
              aria-describedby={form.errors.termsAccepted ? "terms-accepted-error" : undefined}
              checked={form.data.termsAccepted}
              onCheckedChange={(checked) => form.setData("termsAccepted", checked === true)}
            />
            <Label htmlFor="terms-accepted" className="block font-normal leading-relaxed">
              <Trans
                i18nKey="auth.registration.accept"
                components={{
                  terms: <Link href={publicRoutes.legal("terms")} className={legalLink} />,
                  privacy: <Link href={publicRoutes.legal("privacy")} className={legalLink} />,
                }}
              />
            </Label>
          </div>
          {form.errors.termsAccepted && (
            <p id="terms-accepted-error" role="alert" className="text-sm font-medium text-destructive">
              {form.errors.termsAccepted}
            </p>
          )}
        </div>
        <Turnstile action="registration" attempt={attempt} onToken={onToken} error={form.errors.turnstileToken} />
        <Button type="submit" size="lg" disabled={form.processing || (turnstile.required && !form.data.turnstileToken)}>
          {t("auth.registration.submit")}
        </Button>
      </form>
      <p className="mt-8 text-sm text-muted-foreground">
        {t("auth.registration.have_account")} <TextLink href={routes.session.new().url}>{t("nav.sign_in")}</TextLink>
      </p>
    </>
  )
}
