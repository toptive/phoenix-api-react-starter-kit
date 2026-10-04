import { notFound, redirect } from "@tanstack/react-router"
import type { Bootstrap } from "@/api/generated/serializers"
import { paths } from "./paths"
export type Guard = "public" | "guest" | "user" | "manager" | "sudo" | "superadmin" | "multi"
export function guardRoute(guard: Guard, bootstrap: Bootstrap, href: string, now = Date.now()) {
  const auth = bootstrap.auth
  if (guard === "public") return
  if (guard === "guest") {
    if (auth) throw redirect({ href: paths.dashboard })
    return
  }
  if (guard === "superadmin" && (!auth?.superadmin || auth.impersonator)) throw notFound()
  if (!auth) throw redirect({ href: `${paths.signIn}?returnTo=${encodeURIComponent(href)}` })
  if (guard === "manager" && (auth.membership.access !== "full" || !["owner", "admin"].includes(auth.membership.role)))
    throw redirect({ href: "/errors/403" })
  if (
    guard === "sudo" &&
    (!auth.sudoUntil || !Number.isFinite(Date.parse(auth.sudoUntil)) || Date.parse(auth.sudoUntil) <= now)
  )
    throw redirect({ href: `${paths.signIn}?sudo=1&returnTo=${encodeURIComponent(href)}` })
  if (guard === "multi" && bootstrap.app.tenancy !== "multi") throw notFound()
  if (href.split("?")[0] === paths.dashboard && auth.onboardingRequired) throw redirect({ href: paths.onboarding })
}
