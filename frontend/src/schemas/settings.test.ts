import { describe, expect, it } from "vitest"
import { passwordSchema, profileSchema } from "./settings"
import { onboardingSchema, invitationSchema } from "./organizations"
import { limits } from "./limits"

describe("settings inputs", () => {
  it("accepts blank onboarding answers but validates names that were given", () => {
    expect(onboardingSchema.parse({ name: "   " })).toEqual({ name: "" })
    expect(onboardingSchema.safeParse({ name: "a" }).success).toBe(false)
    expect(onboardingSchema.safeParse({ name: "a".repeat(limits.organizationMax + 1) }).success).toBe(false)
    expect(onboardingSchema.parse({ name: "  Team  " })).toEqual({ name: "Team" })
  })
  it("checks password bytes as well as matching confirmation", () => {
    const parse = (password: string, confirmation = password) =>
      passwordSchema.safeParse({ password, passwordConfirmation: confirmation }).success
    expect(parse("a".repeat(limits.passwordMin))).toBe(true)
    expect(parse("a".repeat(limits.passwordMaxBytes))).toBe(true)
    expect(parse("😀".repeat(19))).toBe(false)
    expect(parse("a".repeat(limits.passwordMin), "different")).toBe(false)
    expect(parse("short")).toBe(false)
  })
  it("only accepts supported locales and cannot invite owners", () => {
    expect(profileSchema(["en", "es"]).safeParse({ name: "Ana", locale: "xx" }).success).toBe(false)
    expect(invitationSchema.safeParse({ email: "ana@example.com", role: "owner", access: "full" }).success).toBe(false)
    expect(invitationSchema.safeParse({ email: "ana@example.com", role: "admin", access: "viewer" }).success).toBe(true)
  })
})
