import { Head, useForm } from "@inertiajs/react"
import { MailIcon } from "lucide-react"
import { useCallback, useState } from "react"
import { useTranslation } from "react-i18next"

import { AlertBanner } from "@/components/app/alert-banner"
import { AuthHeading } from "@/components/app/auth-card"
import { FormField } from "@/components/app/form-field"
import { TextLink } from "@/components/app/text-link"
import { Turnstile } from "@/components/app/turnstile"
import { Button, buttonVariants } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Separator } from "@/components/ui/separator"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { routes } from "@/generated/routes"
import { useSharedProps } from "@/hooks/use-shared-props"
import type { SessionNewProps } from "@/generated/pages"

export default function SessionNew({ googleEnabled, emailAvailable, reauthenticating, linkSentTo, newAccount, signupMode, auth }: SessionNewProps) {
  const { t } = useTranslation()
  const link = useForm({ email: auth?.user.email ?? "", turnstileToken: "" })
  const { setData: setLinkData } = link
  const { turnstile } = useSharedProps()
  // A Turnstile token works once: every submit asks the widget for a new one.
  const [linkAttempt, setLinkAttempt] = useState(0)
  const onLinkToken = useCallback((token: string) => setLinkData("turnstileToken", token), [setLinkData])
  const password = useForm({ email: auth?.user.email ?? "", password: "", rememberMe: true })

  link.transform((data) => ({ user: data }))
  password.transform((data) => ({ user: data }))

  return (
    <>
      <Head title={t("auth.session.title")} />
      <AuthHeading
        title={reauthenticating ? t("auth.session.reauth_title") : t("auth.session.title")}
        description={reauthenticating ? t("auth.session.reauth_lead") : t("auth.session.lead")}
      />

      {linkSentTo && (
        <AlertBanner tone="success" title={t("auth.session.link_sent_title")} className="mb-6">
          {t(newAccount ? "auth.session.link_sent_body_new" : "auth.session.link_sent_body", { email: linkSentTo })}
        </AlertBanner>
      )}

      <Tabs defaultValue="link">
        <TabsList className="grid w-full grid-cols-2">
          <TabsTrigger value="link">{t("auth.session.tab_link")}</TabsTrigger>
          <TabsTrigger value="password">{t("auth.session.tab_password")}</TabsTrigger>
        </TabsList>

        <TabsContent value="link" className="pt-4">
          {emailAvailable ? (
            <form
              className="grid gap-5"
              onSubmit={(event) => {
                event.preventDefault()
                link.post(routes.magicLink.create().url, { onFinish: () => setLinkAttempt((value) => value + 1) })
              }}
            >
              <FormField label={t("fields.email")} help={t("auth.session.link_help")} error={link.errors.email}>
                {(id, describedBy) => (
                  <Input id={id} type="email" autoComplete="email" required aria-describedby={describedBy} value={link.data.email} onChange={(e) => link.setData("email", e.target.value)} />
                )}
              </FormField>
              <Turnstile action="magic_link" attempt={linkAttempt} onToken={onLinkToken} error={link.errors.turnstileToken} />
              <Button type="submit" size="lg" disabled={link.processing || (turnstile.required && !link.data.turnstileToken)}>
                <MailIcon aria-hidden="true" /> {t("auth.session.send_link")}
              </Button>
            </form>
          ) : (
            <AlertBanner tone="warning" title={t("auth.unavailable.title")}>
              {t("auth.unavailable.session_body")}
            </AlertBanner>
          )}
        </TabsContent>

        <TabsContent value="password" className="pt-4">
          <form
            className="grid gap-5"
            onSubmit={(event) => {
              event.preventDefault()
              password.post(routes.session.create().url, { onFinish: () => password.reset("password") })
            }}
          >
            <FormField label={t("fields.email")} error={password.errors.email}>
              {(id, describedBy) => (
                <Input id={id} type="email" autoComplete="username" required aria-describedby={describedBy} value={password.data.email} onChange={(e) => password.setData("email", e.target.value)} />
              )}
            </FormField>
            <FormField label={t("fields.password")} help={t("auth.session.password_help")} error={password.errors.password}>
              {(id, describedBy) => (
                <Input id={id} type="password" autoComplete="current-password" required aria-describedby={describedBy} value={password.data.password} onChange={(e) => password.setData("password", e.target.value)} />
              )}
            </FormField>
            <div className="flex items-center gap-2">
              <Checkbox id="rememberMe" checked={password.data.rememberMe} onCheckedChange={(checked) => password.setData("rememberMe", checked === true)} />
              <Label htmlFor="rememberMe" className="font-normal">
                {t("auth.session.remember_me")}
              </Label>
            </div>
            <Button type="submit" size="lg" disabled={password.processing}>
              {t("auth.session.submit")}
            </Button>
          </form>
        </TabsContent>
      </Tabs>

      {googleEnabled && (
        <>
          <div className="my-6 flex items-center gap-3 text-sm text-muted-foreground">
            <Separator className="flex-1" /> {t("auth.session.or")} <Separator className="flex-1" />
          </div>
          <a href={routes.oAuth.new("google").url} className={buttonVariants({ variant: "outline", size: "lg", className: "w-full" })}>
            {t("auth.session.google")}
          </a>
        </>
      )}

      {!auth && signupMode !== "closed" && (
        <p className="mt-8 text-sm text-muted-foreground">
          {t("auth.session.no_account")} <TextLink href={routes.registration.new().url}>{t("nav.sign_up")}</TextLink>
        </p>
      )}
    </>
  )
}
