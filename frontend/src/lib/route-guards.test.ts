import { describe, expect, it } from "vitest"
import { guardRoute } from "./route-guards"
import { safeReturnPath } from "./auth-flow"
import { auth, bootstrap } from "@/test/fixtures"
import type { Bootstrap } from "@/api/generated/serializers"
const signedIn: Bootstrap = { ...bootstrap, auth }
function refusal(run: () => void): unknown {
  try {
    run()
  } catch (error) {
    return error
  }
  throw new Error("Expected route refusal")
}
describe("router guards", () => {
  it("allows public routes and anonymous registration", () => {
    expect(() => guardRoute("public", bootstrap, "/")).not.toThrow()
    expect(() => guardRoute("guest", bootstrap, "/registration/new")).not.toThrow()
  })
  it("redirects signed-in guests to the dashboard", () => {
    expect(refusal(() => guardRoute("guest", signedIn, "/registration/new"))).toMatchObject({
      options: { href: "/dashboard" },
    })
  })
  it("carries the complete return path through a sign-in redirect", () => {
    expect(refusal(() => guardRoute("user", bootstrap, "/settings/sessions?page=2"))).toMatchObject({
      options: { href: "/session/new?returnTo=%2Fsettings%2Fsessions%3Fpage%3D2" },
    })
  })
  it("requires onboarding only from the dashboard", () => {
    const onboarding = { ...bootstrap, auth: { ...auth, onboardingRequired: true } }
    expect(refusal(() => guardRoute("user", onboarding, "/dashboard"))).toMatchObject({
      options: { href: "/onboarding/edit" },
    })
    expect(() => guardRoute("user", onboarding, "/settings/profile/edit")).not.toThrow()
    expect(() => guardRoute("manager", onboarding, "/onboarding/edit")).not.toThrow()
  })
  it("keeps members and viewers out of manager screens", () => {
    for (const membership of [
      { ...auth.membership, role: "member" as const },
      { ...auth.membership, access: "viewer" as const },
    ]) {
      expect(
        refusal(() => guardRoute("manager", { ...bootstrap, auth: { ...auth, membership } }, "/onboarding/edit")),
      ).toMatchObject({ options: { href: "/errors/403" } })
    }
  })
  it("requires a live sudo window and sends its intended target", () => {
    const expired = { ...bootstrap, auth: { ...auth, sudoUntil: "2020-01-01T00:00:00Z" } }
    expect(refusal(() => guardRoute("sudo", expired, "/settings/email/edit"))).toMatchObject({
      options: { href: "/session/new?sudo=1&returnTo=%2Fsettings%2Femail%2Fedit" },
    })
    expect(() => guardRoute("sudo", signedIn, "/settings/email/edit")).not.toThrow()
  })
  it("hides superadmin routes from users and impersonating admins", () => {
    expect(refusal(() => guardRoute("superadmin", signedIn, "/admin"))).toMatchObject({ isNotFound: true })
    expect(
      refusal(() =>
        guardRoute(
          "superadmin",
          { ...bootstrap, auth: { ...auth, superadmin: true, impersonator: auth.user } },
          "/admin",
        ),
      ),
    ).toMatchObject({ isNotFound: true })
    expect(() =>
      guardRoute("superadmin", { ...bootstrap, auth: { ...auth, superadmin: true } }, "/admin"),
    ).not.toThrow()
  })
  it("blocks organization creation in single-tenant mode", () => {
    expect(
      refusal(() =>
        guardRoute("multi", { ...signedIn, app: { ...bootstrap.app, tenancy: "single" } }, "/organizations/new"),
      ),
    ).toMatchObject({ isNotFound: true })
  })
  it("accepts recovery and invitation destinations, rejecting external and looping targets", () => {
    expect(safeReturnPath("/settings/password/edit")).toBe("/settings/password/edit")
    expect(safeReturnPath("/invitations/token")).toBe("/invitations/token")
    for (const path of [
      "https://evil.test",
      "//evil.test",
      "/\\evil.test",
      "/%5cevil.test",
      "/%2fevil.test",
      "/session/new",
      "/auth/callback",
      "/registration/new",
      "/bad\npath",
    ])
      expect(safeReturnPath(path)).toBeNull()
  })
})
