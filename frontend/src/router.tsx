import {
  createRootRouteWithContext,
  createRoute,
  createRouter,
  lazyRouteComponent,
  redirect,
  notFound,
  type ErrorComponentProps,
} from "@tanstack/react-router"
import type { QueryClient } from "@tanstack/react-query"
import { listSearchSchema, translationSearchSchema, billingSearchSchema } from "@/schemas/search"
import { bundledLocales } from "@/i18n"
import { AppShell } from "@/app-shell"
import { bootstrapOptions } from "@/api/hooks/bootstrap"
import { localeOptions, restoreLocale } from "@/api/hooks/locales"
import { captureGoogleCallback } from "@/api/hooks/auth"
import { recordPageView } from "@/api/hooks/public"
import type { Bootstrap } from "@/api/generated/serializers"
import { qk } from "@/api/query-keys"
import { clearApiFailure } from "@/lib/api-failure"
import { ApiError } from "@/api/http"
import { queryClient } from "@/lib/query-client"
import { guardRoute, type Guard } from "@/lib/route-guards"
import { returnPath } from "@/lib/auth-flow"
import { ImpersonationBanner } from "@/components/app/impersonation-banner"
import ErrorShow from "@/pages/errors/show"
import { TextLink } from "@/components/app/text-link"
import { paths } from "@/lib/paths"
import { useTranslation } from "react-i18next"

type Shell = "public" | "auth" | "app" | "settings" | "admin"
declare module "@tanstack/react-router" {
  interface StaticDataRouteOption {
    shell?: Shell
  }
}
interface RouterContext {
  queryClient: QueryClient
}
function RouteError({ error, reset }: ErrorComponentProps) {
  const { t } = useTranslation()
  const message = error instanceof Error ? error.message : "internal_error"
  if (["oauth_failed", "email_not_verified", "invitation_required", "signup_closed", "state_invalid"].includes(message))
    return (
      <div className="space-y-6 p-8">
        <p role="alert">{t(`errors.api.${message}`)}</p>
        <TextLink href={paths.signIn}>{t("nav.sign_in")}</TextLink>
      </div>
    )
  return (
    <>
      <ImpersonationBanner />
      <ErrorShow status={error instanceof ApiError ? error.status : 500} onRetry={reset} />
    </>
  )
}
const rootRoute = createRootRouteWithContext<RouterContext>()({
  component: AppShell,
  errorComponent: RouteError,
  notFoundComponent: () => <ErrorShow status={404} />,
  beforeLoad: async ({ context, location, matches }) => {
    clearApiFailure()
    const knownLocales = context.queryClient.getQueryData<Bootstrap>(qk.bootstrap)?.locales ?? bundledLocales
    const localeParam = matches.at(-1)?.params as { locale?: string } | undefined
    if (
      matches.some((match) => match._notFound) ||
      matches.length === 1 ||
      (localeParam?.locale && !knownLocales.includes(localeParam.locale))
    )
      throw notFound()

    // The Google fragment is processed before bootstrap, including a stale stored bearer.
    if (location.pathname === "/auth/callback") {
      if (!window.location.hash) throw new Error("oauth_failed")
      const destination = await captureGoogleCallback(context.queryClient)
      throw redirect({ href: destination, replace: true })
    }
    const bootstrap = await context.queryClient.ensureQueryData(bootstrapOptions())
    const prefix = location.pathname.split("/")[1] ?? ""
    const search = Object.fromEntries(new URLSearchParams(location.searchStr))
    // Bootstrap supplies the locale contract. On a cold deep link, validateSearch
    // ran before it was available; preserve supported filters after bootstrap.
    const schema =
      location.pathname === paths.adminTranslations
        ? translationSearchSchema
        : ([paths.adminUsers, paths.adminOrganizations, paths.adminAuditEvents] as string[]).includes(location.pathname)
          ? listSearchSchema
          : location.pathname === paths.billing
            ? billingSearchSchema
            : null
    if (schema) {
      const expected = schema.parse(search)
      if (JSON.stringify(expected) !== JSON.stringify(schema.parse(location.search)))
        throw redirect({ to: location.pathname, search: expected, replace: true })
    }
    const requested = bootstrap.locales.includes(prefix) ? prefix : search.locale
    const locale = typeof requested === "string" && bootstrap.locales.includes(requested) ? requested : bootstrap.locale
    restoreLocale(locale)
    await context.queryClient.ensureQueryData(localeOptions(locale, bootstrap.i18nVersion)).catch(() => undefined)
    return { bootstrap }
  },
})
const homeComponent = lazyRouteComponent(() => import("@/pages/home/show"))
const authSearch = (search: Record<string, unknown>): Record<string, string> =>
  Object.fromEntries(
    Object.entries(search)
      .filter(
        ([key, value]) =>
          ["returnTo", "sudo", "email", "newAccount", "locale"].includes(key) &&
          ["string", "number"].includes(typeof value),
      )
      .map(([key, value]) => [key, String(value)]),
  )
const localeSearch = (search: Record<string, unknown>) => ({
  ...(typeof search.locale === "string" ? { locale: search.locale } : {}),
})
const route = (path: string, guard: Guard, shell: Shell, component: typeof homeComponent) =>
  createRoute({
    getParentRoute: () => rootRoute,
    path,
    staticData: { shell },
    validateSearch: ["/admin/users", "/admin/organizations", "/admin/translations", "/admin/audit-events"].includes(
      path,
    )
      ? (search) =>
          path === "/admin/translations" ? translationSearchSchema.parse(search) : listSearchSchema.parse(search)
      : path === "/settings/billing"
        ? (search) => billingSearchSchema.parse(search)
        : shell === "auth"
          ? authSearch
          : localeSearch,
    component,
    beforeLoad: ({ context, location }) => {
      guardRoute(guard, context.bootstrap, location.href)
      if (
        ["/session/new", "/registration/new", "/sudo/new"].includes(location.pathname) &&
        (location.search as Record<string, unknown>).returnTo
      )
        returnPath.set((location.search as Record<string, unknown>).returnTo)
    },
  })
const home = route("/", "public", "public", homeComponent)
const localizedHome = createRoute({
  getParentRoute: () => rootRoute,
  path: "/$locale",
  component: homeComponent,
  beforeLoad: ({ params, context }) => {
    if (!context.bootstrap.locales.includes(params.locale)) throw notFound()
  },
})
const legal = lazyRouteComponent(() => import("@/pages/legal/show"))
const localizedLegal = createRoute({
  getParentRoute: () => rootRoute,
  path: "/$locale/legal/$slug",
  component: legal,
  beforeLoad: ({ params, context }) => {
    if (!context.bootstrap.locales.includes(params.locale)) throw notFound()
  },
})
const routes = [
  home,
  localizedHome,
  route("/legal/$slug", "public", "public", legal),
  localizedLegal,
  route(
    "/registration/new",
    "guest",
    "auth",
    lazyRouteComponent(() => import("@/pages/registration/new")),
  ),
  route(
    "/session/new",
    "public",
    "auth",
    lazyRouteComponent(() => import("@/pages/session/new")),
  ),
  route(
    "/session/check-your-email",
    "public",
    "auth",
    lazyRouteComponent(() => import("@/pages/session/check-your-email")),
  ),
  route(
    "/magic-links/$token",
    "public",
    "auth",
    lazyRouteComponent(() => import("@/pages/magic-links/show")),
  ),
  route(
    "/sudo/new",
    "user",
    "auth",
    lazyRouteComponent(() => import("@/pages/sudo/new")),
  ),
  route(
    "/auth/callback",
    "public",
    "auth",
    lazyRouteComponent(() => import("@/pages/auth/callback")),
  ),
  route(
    "/invitations/$token",
    "public",
    "auth",
    lazyRouteComponent(() => import("@/pages/invitations/show")),
  ),
  route(
    "/email-subscriptions/$token/opt-out",
    "public",
    "auth",
    lazyRouteComponent(() => import("@/pages/email-opt-out/show")),
  ),
  route(
    "/dashboard",
    "user",
    "app",
    lazyRouteComponent(() => import("@/pages/dashboard/show")),
  ),
  route(
    "/onboarding/edit",
    "manager",
    "app",
    lazyRouteComponent(() => import("@/pages/onboarding/edit")),
  ),
  route(
    "/organizations/new",
    "multi",
    "app",
    lazyRouteComponent(() => import("@/pages/organizations/new")),
  ),
  route(
    "/settings/profile/edit",
    "user",
    "settings",
    lazyRouteComponent(() => import("@/pages/settings/profile/edit")),
  ),
  route(
    "/settings/appearance/edit",
    "user",
    "settings",
    lazyRouteComponent(() => import("@/pages/settings/appearance/edit")),
  ),
  route(
    "/settings/email-preferences/edit",
    "user",
    "settings",
    lazyRouteComponent(() => import("@/pages/settings/email-preferences/edit")),
  ),
  route(
    "/settings/sessions",
    "user",
    "settings",
    lazyRouteComponent(() => import("@/pages/settings/sessions/index")),
  ),
  route(
    "/settings/organization/edit",
    "user",
    "settings",
    lazyRouteComponent(() => import("@/pages/settings/organization/edit")),
  ),
  route(
    "/settings/members",
    "user",
    "settings",
    lazyRouteComponent(() => import("@/pages/settings/members/index")),
  ),
  route(
    "/settings/billing",
    "user",
    "settings",
    lazyRouteComponent(() => import("@/pages/settings/billing/show")),
  ),
  route(
    "/settings/email/edit",
    "sudo",
    "settings",
    lazyRouteComponent(() => import("@/pages/settings/email/edit")),
  ),
  route(
    "/settings/password/edit",
    "sudo",
    "settings",
    lazyRouteComponent(() => import("@/pages/settings/password/edit")),
  ),
  route(
    "/settings/account/edit",
    "sudo",
    "settings",
    lazyRouteComponent(() => import("@/pages/settings/account/edit")),
  ),
  route(
    "/settings/email-confirmations/$token",
    "user",
    "settings",
    lazyRouteComponent(() => import("@/pages/settings/email-confirmations/show")),
  ),
  route(
    "/admin",
    "superadmin",
    "admin",
    lazyRouteComponent(() => import("@/pages/admin/dashboard/show")),
  ),
  route(
    "/admin/users",
    "superadmin",
    "admin",
    lazyRouteComponent(() => import("@/pages/admin/users/index")),
  ),
  route(
    "/admin/users/$id",
    "superadmin",
    "admin",
    lazyRouteComponent(() => import("@/pages/admin/users/show")),
  ),
  route(
    "/admin/organizations",
    "superadmin",
    "admin",
    lazyRouteComponent(() => import("@/pages/admin/organizations/index")),
  ),
  route(
    "/admin/organizations/$id",
    "superadmin",
    "admin",
    lazyRouteComponent(() => import("@/pages/admin/organizations/show")),
  ),
  route(
    "/admin/translations",
    "superadmin",
    "admin",
    lazyRouteComponent(() => import("@/pages/admin/translations/index")),
  ),
  route(
    "/admin/legal-documents",
    "superadmin",
    "admin",
    lazyRouteComponent(() => import("@/pages/admin/legal-documents/index")),
  ),
  route(
    "/admin/legal-documents/$slug",
    "superadmin",
    "admin",
    lazyRouteComponent(() => import("@/pages/admin/legal-documents/show")),
  ),
  route(
    "/admin/audit-events",
    "superadmin",
    "admin",
    lazyRouteComponent(() => import("@/pages/admin/audit-events/index")),
  ),
  route("/errors/403", "public", "public", () => <ErrorShow status={403} />),
  route("/errors/404", "public", "public", () => <ErrorShow status={404} />),
  route("/errors/500", "public", "public", () => <ErrorShow status={500} />),
]
export const routeTree = rootRoute.addChildren(routes)
export const router = createRouter({
  routeTree,
  context: { queryClient },
  defaultPreload: "intent",
  defaultErrorComponent: RouteError,
})
router.subscribe("onResolved", ({ toLocation }) => {
  if (
    toLocation.pathname === "/" ||
    bundledLocales.some((locale) => toLocation.pathname === `/${locale}`) ||
    toLocation.pathname.includes("/legal/")
  ) {
    void recordPageView(
      toLocation.pathname === "/" ? "home" : toLocation.pathname.replaceAll("/", "-").slice(0, 80),
    ).catch(() => undefined)
  }
})
