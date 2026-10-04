import { QueryClient } from "@tanstack/react-query"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { i18n } from "@/i18n"
import { localeOptions, restoreLocale } from "./locales"
import { configureApi } from "../http"
import { clearApiFailure } from "@/lib/api-failure"

const fetchStub = vi.fn<typeof fetch>()
beforeEach(() => {
  localStorage.clear()
  clearApiFailure()
  configureApi("")
  vi.stubGlobal("fetch", fetchStub)
  fetchStub.mockReset()
})
afterEach(() => {
  vi.unstubAllGlobals()
  void i18n.changeLanguage("en")
})
describe("locale catalogue", () => {
  it("renders the CSV fallback before an API catalogue has loaded", () => {
    restoreLocale("es")
    expect(i18n.t("auth.session.title")).toBe("Ingresá")
  })
  it("stores admin text edits, revalidates with an ETag and refreshes on a new version", async () => {
    const qc = new QueryClient()
    fetchStub.mockResolvedValueOnce(
      Response.json({ data: { "auth.session.title": "Custom sign-in" }, meta: { locale: "en", version: "v1" } }),
    )
    await qc.fetchQuery(localeOptions("en", "v1"))
    expect(i18n.t("auth.session.title")).toBe("Custom sign-in")
    expect(localStorage.getItem("starterkit:catalogue:en")).toContain('"en:v1"'.replaceAll('"', '\\"'))
    qc.clear()
    fetchStub.mockResolvedValueOnce(new Response(null, { status: 304 }))
    expect(await qc.fetchQuery(localeOptions("en", "v1"))).toEqual({ "auth.session.title": "Custom sign-in" })
    expect(fetchStub.mock.calls[1]?.[1]?.headers).toMatchObject({ "If-None-Match": '"en:v1"' })
    fetchStub.mockResolvedValueOnce(
      Response.json({ data: { "auth.session.title": "New sign-in" }, meta: { locale: "en", version: "v2" } }),
    )
    await qc.fetchQuery(localeOptions("en", "v2"))
    expect(i18n.t("auth.session.title")).toBe("New sign-in")
    qc.clear()
  })
})
