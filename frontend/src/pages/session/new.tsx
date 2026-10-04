import { limits } from "@/schemas/limits"
import { useNavigate, useSearch } from "@tanstack/react-router"
import { useTranslation } from "react-i18next"
import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { useAppConfig } from "@/api/hooks/bootstrap"
import { googleStartUrl, useSignIn } from "@/api/hooks/auth"
import { AuthHeading } from "@/components/app/auth-card"
import { FormField } from "@/components/app/form-field"
import { FormError } from "@/components/app/form-error"
import { TextLink } from "@/components/app/text-link"
import { MagicLinkForm } from "@/components/app/magic-link-form"
import { AlertBanner } from "@/components/app/alert-banner"
import { Button, buttonVariants } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { signInSchema } from "@/schemas/auth"
import { applyFormErrors, fieldMessage } from "@/lib/form-errors"
import { destinationAfterAuth, returnPath } from "@/lib/auth-flow"
import { paths } from "@/lib/paths"
import SudoPage from "@/pages/sudo/new"

export default function SignInPage() {
  const { auth } = useAppConfig()
  const search = useSearch({ strict: false }) as {
    sudo?: string
    email?: string
    newAccount?: string
    returnTo?: string
  }
  if (search.sudo === "1" && auth) return <SudoPage />
  return <SignInForms />
}
function SignInForms() {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const { app } = useAppConfig()
  const search = useSearch({ strict: false }) as { email?: string; newAccount?: string }
  const password = useForm({
    resolver: zodResolver(signInSchema),
    defaultValues: { email: search.email ?? "", password: "" },
  })
  const login = useSignIn()
  return (
    <>
      <title>{t("auth.session.title")}</title>
      <AuthHeading title={t("auth.session.title")} description={t("auth.session.lead")} />
      {search.email && (
        <AlertBanner tone="success" title={t("auth.session.link_sent_title")} className="mb-6">
          {t(search.newAccount === "1" ? "auth.session.link_sent_body_new" : "auth.session.link_sent_body", {
            email: search.email,
          })}
        </AlertBanner>
      )}
      <Tabs defaultValue={app.emailAvailable ? "link" : "password"}>
        <TabsList className="grid w-full grid-cols-2">
          <TabsTrigger value="link">{t("auth.session.tab_link")}</TabsTrigger>
          <TabsTrigger value="password">{t("auth.session.tab_password")}</TabsTrigger>
        </TabsList>
        <TabsContent value="link" className="pt-4">
          {app.emailAvailable ? (
            <MagicLinkForm email={search.email} />
          ) : (
            <AlertBanner tone="warning" title={t("auth.unavailable.title")}>
              {t("auth.unavailable.session_body")}
            </AlertBanner>
          )}
        </TabsContent>
        <TabsContent value="password" className="pt-4">
          <form
            noValidate
            className="grid gap-5"
            onSubmit={password.handleSubmit(async (input) => {
              try {
                await login.mutateAsync(input)
                void navigate({ to: destinationAfterAuth() })
              } catch (error) {
                applyFormErrors(error, password.setError)
              } finally {
                password.resetField("password")
              }
            })}
          >
            <FormField label={t("fields.email")} error={fieldMessage(password.formState.errors.email?.message, { count: limits.emailMax })}>
              {(id, describedBy) => (
                <Input
                  id={id}
                  aria-describedby={describedBy}
                  type="email"
                  autoComplete="username"
                  {...password.register("email")}
                />
              )}
            </FormField>
            <FormField
              label={t("fields.password")}
              help={t("auth.session.password_help")}
              error={fieldMessage(password.formState.errors.password?.message)}
            >
              {(id, describedBy) => (
                <Input
                  id={id}
                  aria-describedby={describedBy}
                  type="password"
                  autoComplete="current-password"
                  {...password.register("password")}
                />
              )}
            </FormField>
            <FormError message={password.formState.errors.root?.message} />
            <Button size="lg" type="submit" disabled={login.isPending}>
              {t("auth.session.submit")}
            </Button>
            <p className="text-sm text-muted-foreground">{t("auth.session.forgot_help")}</p>
          </form>
        </TabsContent>
      </Tabs>
      {app.googleEnabled && (
        <a
          href={googleStartUrl(returnPath.get() ?? undefined)}
          className={buttonVariants({ variant: "outline", size: "lg", className: "mt-6 w-full" })}
        >
          {t("auth.session.google")}
        </a>
      )}
      {app.signupMode !== "closed" && app.emailAvailable && (
        <p className="mt-8 text-sm text-muted-foreground">
          {t("auth.session.no_account")} <TextLink href={paths.register}>{t("nav.sign_up")}</TextLink>
        </p>
      )}
    </>
  )
}
