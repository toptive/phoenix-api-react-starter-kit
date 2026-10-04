import { useApiFailure } from "@/lib/api-failure"
import { lazy, Suspense } from "react"
import { Outlet, useRouterState } from "@tanstack/react-router"
import { useTranslation } from "react-i18next"
import { useBootstrap } from "@/api/hooks/bootstrap"
import { useLocales } from "@/api/hooks/locales"
import { SudoProvider } from "@/components/app/sudo-dialog"
import { AppErrorBoundary } from "@/components/app/error-boundary"
import { ImpersonationBanner } from "@/components/app/impersonation-banner"
import ErrorShow from "@/pages/errors/show"
import { ApiError } from "@/api/http"

const PublicLayout = lazy(() => import("@/layouts/public-layout").then((m) => ({ default: m.PublicLayout })))
const AuthLayout = lazy(() => import("@/layouts/auth-layout").then((m) => ({ default: m.AuthLayout })))
const AppLayout = lazy(() => import("@/layouts/app-layout").then((m) => ({ default: m.AppLayout })))
const AdminLayout = lazy(() => import("@/layouts/admin-layout").then((m) => ({ default: m.AdminLayout })))
const SettingsLayout = lazy(() => import("@/layouts/settings-layout").then((m) => ({ default: m.SettingsLayout })))

export function AppShell() {
  const missing = useRouterState({
    select: (state) => state.matches.some((match) => match.status === "notFound" || match._notFound),
  })
  const pathname = useRouterState({ select: (state) => state.location.pathname })
  return (
    <>
      <ImpersonationBanner />
      <AppErrorBoundary key={pathname}>{missing ? <ErrorShow status={404} /> : <BootstrapShell />}</AppErrorBoundary>
    </>
  )
}
function BootstrapShell() {
  const status = useApiFailure()
  const bootstrap = useBootstrap()
  const { t } = useTranslation()
  if (status && bootstrap.data) return <ReadyShell errorStatus={status} />
  if (bootstrap.error) return <ErrorShow status={bootstrap.error instanceof ApiError ? bootstrap.error.status : 500} />
  if (!bootstrap.data)
    return (
      <p role="status" className="p-8">
        {t("common.loading")}
      </p>
    )
  return <ReadyShell />
}
function ReadyShell({ errorStatus }: { errorStatus?: number }) {
  const { i18n, t } = useTranslation()
  const { data } = useBootstrap()
  useLocales(i18n.language, data?.i18nVersion ?? "")
  const shell = useRouterState({ select: (state) => state.matches.at(-1)?.staticData.shell ?? "public" })
  const content = errorStatus ? <ErrorShow status={errorStatus} /> : <Outlet />
  return (
    <SudoProvider>
      <Suspense
        fallback={
          <p role="status" className="p-8">
            {t("common.loading")}
          </p>
        }
      >
        {shell === "auth" ? (
          <AuthLayout>{content}</AuthLayout>
        ) : shell === "app" ? (
          <AppLayout>{content}</AppLayout>
        ) : shell === "settings" ? (
          <AppLayout>
            <SettingsLayout>{content}</SettingsLayout>
          </AppLayout>
        ) : shell === "admin" ? (
          <AdminLayout>{content}</AdminLayout>
        ) : (
          <PublicLayout>{content}</PublicLayout>
        )}
      </Suspense>
    </SudoProvider>
  )
}
