import { screen } from "@testing-library/react"
import type { ComponentProps } from "react"
import { beforeEach, describe, expect, it, vi } from "vitest"

import RegistrationNew from "@/pages/registration/new"
import SessionNew from "@/pages/session/new"
import { renderWithI18n } from "@/test/render"

// The server refuses a form behind Plugs.VerifyTurnstile without a token, so every page
// that posts to one must render the widget whenever protection is ON.
const shared = vi.hoisted(() => ({
  locale: "en",
  locales: ["en", "es"],
  auth: null,
  turnstile: { required: true, siteKey: "public-key" as string | null },
}))

vi.mock("@inertiajs/react", async (original) => ({
  ...(await original<Record<string, unknown>>()),
  Head: () => null,
  usePage: () => ({ props: shared }),
}))
vi.mock("@/lib/turnstile-client", () => ({ loadWidget: () => new Promise(() => {}) }))

// jsdom has no ResizeObserver; the Radix checkbox measures itself with one.
globalThis.ResizeObserver ??= class {
  observe() {}
  unobserve() {}
  disconnect() {}
}

const registration = {
  email: "",
  emailAvailable: true,
  signupMode: "open",
} as ComponentProps<typeof RegistrationNew>

const session = {
  googleEnabled: false,
  emailAvailable: true,
  reauthenticating: false,
  linkSentTo: null,
  newAccount: false,
  signupMode: "open",
  auth: null,
} as unknown as ComponentProps<typeof SessionNew>

describe("Turnstile on the anonymous forms", () => {
  beforeEach(() => {
    shared.turnstile = { required: true, siteKey: "public-key" }
  })

  it("required: sign-up renders the widget and waits for a token", () => {
    const { container } = renderWithI18n(<RegistrationNew {...registration} />)

    expect(container.querySelector('[data-turnstile="registration"]')).not.toBeNull()
    expect(screen.getByRole("button", { name: "Create account" })).toHaveProperty("disabled", true)
  })

  it("required: the sign-in link form renders the widget", () => {
    const { container } = renderWithI18n(<SessionNew {...session} />)

    expect(container.querySelector('[data-turnstile="magic_link"]')).not.toBeNull()
  })

  it("off: no widget, the forms submit as before", () => {
    shared.turnstile = { required: false, siteKey: null }
    const { container } = renderWithI18n(<RegistrationNew {...registration} />)

    expect(container.querySelector("[data-turnstile]")).toBeNull()
    expect(screen.getByRole("button", { name: "Create account" })).toHaveProperty("disabled", false)
  })
})
