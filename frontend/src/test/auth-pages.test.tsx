import { act, fireEvent, render, screen, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { createMemoryHistory, createRouter, RouterProvider } from "@tanstack/react-router"
import { I18nextProvider } from "react-i18next"
import { beforeEach, afterEach, describe, expect, it, vi } from "vitest"
import { clearApiFailure } from "@/lib/api-failure"
import { routeTree } from "@/router"
import { createI18n } from "@/i18n"
import { auth, bootstrap, session } from "./fixtures"
import { clearTokens, getToken, setToken, configureApi, setUnauthorizedHandler } from "@/api/http"
import type { Bootstrap } from "@/api/generated/serializers"
import GoogleCallbackPage from "@/pages/auth/callback"
import { captureGoogleCallback } from "@/api/hooks/auth"

let current: Bootstrap
let responders: Record<string, () => Response>
const requests: { path: string; method: string; body?: unknown }[] = []
const clients: QueryClient[] = []
function envelope(data: unknown, status = 200) {
  return Response.json({ data }, { status })
}
async function openPage(path: string) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  clients.push(queryClient)
  const router = createRouter({
    routeTree,
    history: createMemoryHistory({ initialEntries: [path] }),
    context: { queryClient },
    defaultPendingMinMs: 0,
  })
  await act(async () => {
    await router.load()
  })
  render(
    <I18nextProvider i18n={createI18n("en")}>
      <QueryClientProvider client={queryClient}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </I18nextProvider>,
  )
  return { router, queryClient }
}
beforeEach(() => {
  clearApiFailure()
  localStorage.clear()
  sessionStorage.clear()
  configureApi("")
  requests.length = 0
  current = structuredClone(bootstrap)
  responders = {}
  window.history.replaceState(null, "", "/")
  setUnauthorizedHandler(vi.fn())
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url: string, init?: RequestInit) => {
      const path = new URL(url, "http://localhost").pathname
      const method = init?.method ?? "GET"
      requests.push({ path, method, ...(init?.body ? { body: JSON.parse(String(init.body)) } : {}) })
      const response = responders[`${method} ${path}`]
      if (response) return response()
      if (path === "/api/v1/bootstrap") return envelope(current)
      if (path.startsWith("/api/v1/locales/")) return envelope({})
      return Response.json({ error: { code: "not_found", message: "Missing", details: {} } }, { status: 404 })
    }),
  )
})
afterEach(() => {
  for (const qc of clients.splice(0)) qc.clear()
  clearTokens()
  vi.unstubAllGlobals()
  setUnauthorizedHandler()
})
describe("auth pages", () => {
  it("renders unknown routes without requesting the API", async () => {
    await openPage("/missing/page")
    expect(await screen.findByRole("heading", { name: createI18n("en").t("errors.page.404.title") })).toBeTruthy()
    expect(requests).toHaveLength(0)
  })
  it("renders sign-in and maps server validation onto the email field", async () => {
    responders["POST /api/v1/auth/magic-links"] = () =>
      Response.json(
        {
          error: {
            code: "validation_failed",
            message: "Fix it",
            details: { email: [{ key: "validation.email_format", message: "Invalid" }] },
          },
        },
        { status: 422 },
      )
    await openPage("/session/new")
    fireEvent.change(await screen.findByLabelText("Email"), { target: { value: "ana@example.com" } })
    fireEvent.click(screen.getByRole("button", { name: "Send me the link" }))
    await waitFor(() =>
      expect(screen.getByRole("alert").textContent).toBe(createI18n("en").t("validation.email_format")),
    )
    expect(requests.find((r) => r.method === "POST")?.body).toMatchObject({ email: "ana@example.com" })
  })
  it("signs in with a password, replaces the token and refetches bootstrap", async () => {
    responders["POST /api/v1/auth/sessions"] = () => {
      current = { ...bootstrap, auth }
      return envelope(session, 201)
    }
    const { router } = await openPage("/session/new?returnTo=%2Fsettings%2Fprofile%2Fedit")
    fireEvent.mouseDown(await screen.findByRole("tab", { name: "Use a password" }), { button: 0, ctrlKey: false })
    fireEvent.change(screen.getByLabelText("Email"), { target: { value: "ana@example.com" } })
    fireEvent.change(screen.getByLabelText("Password"), { target: { value: "correct-password" } })
    fireEvent.click(screen.getByRole("button", { name: "Sign in" }))
    await waitFor(() => expect(getToken()).toBe("new-bearer"))
    await waitFor(() => expect(router.state.location.pathname).toBe("/settings/profile/edit"))
  })
  it("renders registration, keeps the review step and submits flat consent data", async () => {
    responders["POST /api/v1/auth/registrations"] = () => envelope({ email: "ana@example.com", newAccount: true }, 202)
    const { router } = await openPage("/registration/new?email=ana%40example.com")
    fireEvent.change(await screen.findByLabelText("Your name"), { target: { value: "Ana" } })
    fireEvent.click(screen.getByRole("button", { name: "Continue" }))
    await screen.findByLabelText("Email")
    fireEvent.click(screen.getByRole("button", { name: "Continue" }))
    fireEvent.click(await screen.findByRole("checkbox"))
    fireEvent.click(screen.getByRole("button", { name: "Continue" }))
    await screen.findByRole("heading", { name: "Review your answers" })
    fireEvent.click(screen.getByRole("button", { name: "Create account" }))
    await waitFor(() => expect(router.state.location.pathname).toBe("/session/new"))
    expect(requests.find((r) => r.path.endsWith("/registrations"))?.body).toMatchObject({
      name: "Ana",
      email: "ana@example.com",
      termsAccepted: true,
      locale: "en",
    })
  })
  it("hides unavailable email and registration actions", async () => {
    current = { ...bootstrap, app: { ...bootstrap.app, emailAvailable: false, signupMode: "closed" } }
    await openPage("/session/new")
    expect(await screen.findByLabelText("Password")).toBeTruthy()
    expect(screen.queryByRole("button", { name: "Send me the link" })).toBeNull()
    expect(screen.queryByRole("link", { name: "Create account" })).toBeNull()
  })
  it("renders check-your-email with the requested address", async () => {
    await openPage("/session/check-your-email?email=ana%40example.com")
    expect((await screen.findByText(/ana@example.com/)).textContent).toContain("ana@example.com")
  })
  it("renders confirmation without consuming the magic link until the button", async () => {
    responders["GET /api/v1/auth/magic-links/mail-token"] = () =>
      envelope({ email: "ana@example.com", confirmed: false })
    responders["POST /api/v1/auth/magic-links/mail-token/session"] = () => {
      current = { ...bootstrap, auth }
      return envelope(session, 201)
    }
    const { router } = await openPage("/magic-links/mail-token")
    const button = await screen.findByRole("button", { name: "Confirm and sign in" })
    expect(requests.filter((r) => r.method === "POST")).toHaveLength(0)
    fireEvent.click(button)
    await waitFor(() => expect(router.state.location.pathname).toBe("/dashboard"))
    expect(getToken()).toBe("new-bearer")
  })
  it("renders forgot-password and requests a magic link for recovery", async () => {
    responders["POST /api/v1/auth/magic-links"] = () => envelope({ email: "ana@example.com", newAccount: false }, 202)
    const { router } = await openPage("/password-resets/new")
    fireEvent.change(await screen.findByLabelText("Email"), { target: { value: "ana@example.com" } })
    fireEvent.click(screen.getByRole("button", { name: "Send me the link" }))
    await waitFor(() => expect(router.state.location.pathname).toBe("/session/check-your-email"))
    expect(sessionStorage.getItem("starterkit:return-to")).toBe("/password-resets/edit")
  })
  it("renders reset-password, validates matching values and stores the rotated token", async () => {
    current = { ...bootstrap, auth }
    setToken("old")
    responders["PUT /api/v1/settings/password"] = () => envelope(session)
    const { router } = await openPage("/password-resets/edit")
    fireEvent.change(await screen.findByLabelText("Password"), { target: { value: "new-long-password" } })
    fireEvent.change(screen.getByLabelText("Type the password again"), { target: { value: "different-password" } })
    fireEvent.click(screen.getByRole("button", { name: "Save password" }))
    await screen.findByRole("alert")
    expect(requests.some((r) => r.method === "PUT")).toBe(false)
    fireEvent.change(screen.getByLabelText("Type the password again"), { target: { value: "new-long-password" } })
    fireEvent.click(screen.getByRole("button", { name: "Save password" }))
    await waitFor(() => expect(router.state.location.pathname).toBe("/dashboard"))
    expect(getToken()).toBe("new-bearer")
  })
  it("renders sudo and posts reauthentication rather than a new session", async () => {
    current = { ...bootstrap, auth: { ...auth, sudoUntil: null } }
    setToken("same-session")
    responders["POST /api/v1/auth/sudo"] = () => {
      current = { ...bootstrap, auth }
      return envelope({ sudoUntil: auth.sudoUntil })
    }
    const { router } = await openPage("/session/new?sudo=1&returnTo=%2Fsettings%2Femail%2Fedit")
    fireEvent.change(await screen.findByLabelText("Password"), { target: { value: "correct-password" } })
    fireEvent.click(screen.getByRole("button", { name: "Sign in" }))
    await waitFor(() => expect(router.state.location.pathname).toBe("/settings/email/edit"))
    expect(getToken()).toBe("same-session")
    expect(requests.some((r) => r.path === "/api/v1/auth/sessions")).toBe(false)
  })
  it("renders Google callback and removes the fragment before bootstrap", async () => {
    render(
      <I18nextProvider i18n={createI18n("en")}>
        <GoogleCallbackPage />
      </I18nextProvider>,
    )
    expect(screen.getByRole("status").textContent).toBe("Finishing your sign-in…")
    window.history.replaceState(null, "", "/auth/callback#token=google-bearer&returnTo=%2Fsettings%2Fprofile%2Fedit")
    current = { ...bootstrap, auth }
    const qc = new QueryClient()
    clients.push(qc)
    expect(await captureGoogleCallback(qc)).toBe("/settings/profile/edit")
    expect(window.location.hash).toBe("")
    expect(getToken()).toBe("google-bearer")
  })
  it("renders email-change confirmation with a scanner-safe button", async () => {
    current = { ...bootstrap, auth }
    setToken("same-session")
    responders["GET /api/v1/settings/email-confirmations/email-token"] = () => envelope({ email: "new@example.com" })
    await openPage("/settings/email-confirmations/email-token")
    expect(await screen.findByRole("button", { name: "Change my email" })).toBeTruthy()
    expect(requests.filter((r) => r.method === "POST")).toHaveLength(0)
  })
})
