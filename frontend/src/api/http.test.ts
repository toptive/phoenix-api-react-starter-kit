import { beforeEach, afterEach, describe, expect, it, vi } from "vitest"
import { reportApiFailure } from "@/lib/api-failure"
import { toast } from "sonner"
import {
  api,
  ApiError,
  configureApi,
  setToken,
  getToken,
  clearToken,
  TOKEN_KEY,
  ADMIN_TOKEN_KEY,
  setUnauthorizedHandler,
} from "./http"
import { apiV1Bootstrap, apiV1AuthSessions, apiV1AuthSudo, apiV1Locales } from "./generated/routes"
import { i18n } from "@/i18n"

vi.mock("@/lib/api-failure", () => ({ reportApiFailure: vi.fn() }))
vi.mock("sonner", () => ({ toast: { error: vi.fn() } }))
const fetchStub = vi.fn<typeof fetch>()
beforeEach(() => {
  localStorage.clear()
  configureApi("")
  vi.stubGlobal("fetch", fetchStub)
  fetchStub.mockReset()
  vi.mocked(reportApiFailure).mockClear()
  void i18n.changeLanguage("en")
})
afterEach(() => {
  setUnauthorizedHandler()
  vi.unstubAllGlobals()
})
describe("HTTP transport", () => {
  it("unwraps data without losing pagination metadata, using the current locale and bearer", async () => {
    setToken("opaque-token")
    void i18n.changeLanguage("es")
    fetchStub.mockResolvedValue(
      Response.json({ data: [{ id: "1" }], meta: { pagination: { page: 1, perPage: 25, total: 1, totalPages: 1 } } }),
    )
    const result = await api.get(apiV1Bootstrap.show())
    expect(result.data).toEqual([{ id: "1" }])
    expect(result.meta?.pagination?.total).toBe(1)
    expect(fetchStub).toHaveBeenCalledWith(
      "/api/v1/bootstrap",
      expect.objectContaining({
        method: "GET",
        headers: { Accept: "application/json", "Accept-Language": "es", Authorization: "Bearer opaque-token" },
      }),
    )
    expect(localStorage.getItem(TOKEN_KEY)).toBe("opaque-token")
    clearToken()
    expect(getToken()).toBeNull()
  })
  it("configures native routes and requests together without prefixing the origin twice", async () => {
    configureApi("https://api.example.com/api/v1/")
    fetchStub.mockResolvedValue(Response.json({ data: { ready: true } }))
    expect(apiV1Bootstrap.show().url).toBe("https://api.example.com/api/v1/bootstrap")
    await api.get(apiV1Bootstrap.show())
    expect(fetchStub.mock.calls[0]?.[0]).toBe("https://api.example.com/api/v1/bootstrap")
  })
  it("maps validation errors, including translation bindings", async () => {
    const details = {
      password: [{ key: "validation.length_min", message: "Use at least 12 characters.", bindings: { count: 12 } }],
    }
    fetchStub.mockResolvedValue(
      Response.json({ error: { code: "validation_failed", message: "Fix the form", details } }, { status: 422 }),
    )
    await expect(api.post(apiV1AuthSessions.create(), { email: "a@b.com", password: "short" })).rejects.toMatchObject({
      name: "ApiError",
      status: 422,
      code: "validation_failed",
      message: "Fix the form",
      details,
    })
    expect(fetchStub.mock.calls[0]?.[1]?.body).toBe('{"email":"a@b.com","password":"short"}')
  })
  it("clears both tokens and invokes sign-in navigation after an authenticated 401", async () => {
    const redirect = vi.fn()
    setUnauthorizedHandler(redirect)
    setToken("expired")
    localStorage.setItem(ADMIN_TOKEN_KEY, "admin")
    fetchStub.mockResolvedValue(
      Response.json({ error: { code: "session_expired", message: "Expired", details: {} } }, { status: 401 }),
    )
    await expect(api.get(apiV1Bootstrap.show())).rejects.toBeInstanceOf(ApiError)
    expect(getToken()).toBeNull()
    expect(localStorage.getItem(ADMIN_TOKEN_KEY)).toBeNull()
    expect(redirect).toHaveBeenCalledOnce()
  })
  it("does not clear a newer session when an older in-flight request returns 401", async () => {
    const redirect = vi.fn()
    setUnauthorizedHandler(redirect)
    setToken("old-session")
    fetchStub.mockImplementation(async () => {
      setToken("new-session")
      return Response.json({ error: { code: "session_expired", message: "Expired", details: {} } }, { status: 401 })
    })
    await expect(api.get(apiV1Bootstrap.show())).rejects.toMatchObject({ status: 401 })
    expect(getToken()).toBe("new-session")
    expect(redirect).not.toHaveBeenCalled()
  })
  it("leaves an existing token untouched for an anonymous password refusal", async () => {
    const redirect = vi.fn()
    setUnauthorizedHandler(redirect)
    setToken("existing")
    fetchStub.mockResolvedValue(
      Response.json({ error: { code: "invalid_credentials", message: "Try again", details: {} } }, { status: 401 }),
    )
    await expect(api.post(apiV1AuthSessions.create(), {}, { anonymous: true })).rejects.toMatchObject({ status: 401 })
    expect(getToken()).toBe("existing")
    expect(redirect).not.toHaveBeenCalled()
    expect(fetchStub.mock.calls[0]?.[1]?.headers).not.toHaveProperty("Authorization")
  })
  it("keeps the authenticated session when sudo rejects a password", async () => {
    const redirect = vi.fn()
    setUnauthorizedHandler(redirect)
    setToken("existing")
    fetchStub.mockResolvedValue(
      Response.json({ error: { code: "invalid_credentials", message: "Try again", details: {} } }, { status: 401 }),
    )
    await expect(api.post(apiV1AuthSudo.create(), { password: "wrong" })).rejects.toMatchObject({
      code: "invalid_credentials",
    })
    expect(getToken()).toBe("existing")
    expect(redirect).not.toHaveBeenCalled()
  })
  it("leaves sudo and unavailable-email failures in the current form", async () => {
    for (const [status, code] of [
      [403, "sudo_required"],
      [503, "email_unavailable"],
      [503, "ai_not_configured"],
      [503, "ai_unavailable"],
    ] as const) {
      fetchStub.mockResolvedValue(Response.json({ error: { code, message: "Try again", details: {} } }, { status }))
      await expect(api.post(apiV1AuthSessions.create())).rejects.toMatchObject({ code, status })
    }
    expect(reportApiFailure).not.toHaveBeenCalled()
  })
  it("toasts rate-limit messages and still rejects for the caller", async () => {
    fetchStub.mockResolvedValue(
      Response.json(
        { error: { code: "rate_limited", message: "Wait a moment", details: { retryAfter: 30 } } },
        { status: 429, headers: { "Retry-After": "30" } },
      ),
    )
    await expect(api.get(apiV1Bootstrap.show())).rejects.toMatchObject({ status: 429 })
    expect(toast.error).toHaveBeenCalledWith("Wait a moment", {
      description: i18n.t("errors.retry_after", { count: 30 }),
    })
  })
  it("accepts empty 204 and conditional 304 responses", async () => {
    fetchStub
      .mockResolvedValueOnce(new Response(null, { status: 204 }))
      .mockResolvedValueOnce(new Response(null, { status: 304 }))
    expect(await api.del(apiV1AuthSessions.destroy())).toEqual({ data: undefined })
    expect(await api.get(apiV1Locales.show("en"))).toEqual({ data: undefined })
  })
  it("maps non-JSON failures rather than leaking a parser error", async () => {
    fetchStub.mockResolvedValue(new Response("Proxy failure", { status: 500 }))
    await expect(api.get(apiV1Bootstrap.show())).rejects.toMatchObject({ status: 500, code: "internal_error" })
  })
})
