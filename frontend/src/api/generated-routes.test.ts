import { afterEach, describe, expect, it } from "vitest"
import {
  apiV1AuthMagicLinkSession,
  apiV1AdminLegalPublication,
  apiV1AdminTranslation,
  apiV1SettingsSession,
  apiV1AuthSession,
} from "./generated/routes"
import { setRoutesBaseUrl } from "./generated/routes/runtime"
afterEach(() => setRoutesBaseUrl(""))
describe("generated route contract", () => {
  it("encodes parameter segments and keeps query values out of the path", () => {
    expect(apiV1AuthMagicLinkSession.create("a/b?c")).toEqual({
      method: "post",
      url: "/api/v1/auth/magic-links/a%2Fb%3Fc/session",
    })
    expect(
      apiV1AdminTranslation.update("auth.session.title", {
        query: { locale: "es", q: "words & dots", missing: undefined },
      }),
    ).toEqual({ method: "put", url: "/api/v1/admin/translations/auth.session.title?locale=es&q=words%20%26%20dots" })
  })
  it("accepts multiple named parameters and a native API origin", () => {
    setRoutesBaseUrl("https://api.example.com/")
    expect(apiV1AdminLegalPublication.create({ slug: "terms", number: 2 })).toEqual({
      method: "post",
      url: "https://api.example.com/api/v1/admin/legal-documents/terms/versions/2/publication",
    })
  })
  it("uses the contract's plural session create and singular session delete", () => {
    expect(apiV1AuthSession.create()).toEqual({ method: "post", url: "/api/v1/auth/sessions" })
    expect(apiV1AuthSession.delete()).toEqual({ method: "delete", url: "/api/v1/auth/session" })
    expect(apiV1SettingsSession.delete("device-id")).toEqual({
      method: "delete",
      url: "/api/v1/settings/sessions/device-id",
    })
  })
})
