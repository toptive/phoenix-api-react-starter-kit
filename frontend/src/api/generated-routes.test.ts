import { afterEach, describe, expect, it } from "vitest"
import {
  apiV1AuthMagicLinksSessions,
  apiV1AdminLegalDocumentsVersionsPublication,
  apiV1AdminTranslations,
  apiV1SettingsSessions,
  apiV1AuthSessions,
} from "./generated/routes"
import { setBaseUrl } from "./generated/routes/runtime"
afterEach(() => setBaseUrl(""))
describe("generated route contract", () => {
  it("encodes parameter segments and keeps query values out of the path", () => {
    expect(apiV1AuthMagicLinksSessions.create("a/b?c")).toEqual({
      method: "post",
      url: "/api/v1/auth/magic-links/a%2Fb%3Fc/session",
    })
    expect(
      apiV1AdminTranslations.update("auth.session.title", {
        query: { locale: "es", q: "words & dots", missing: undefined },
      }),
    ).toEqual({ method: "put", url: "/api/v1/admin/translations/auth.session.title?locale=es&q=words%20%26%20dots" })
  })
  it("accepts multiple positional parameters and a native API origin", () => {
    setBaseUrl("https://api.example.com/")
    expect(apiV1AdminLegalDocumentsVersionsPublication.create("terms", 2)).toEqual({
      method: "post",
      url: "https://api.example.com/api/v1/admin/legal-documents/terms/versions/2/publication",
    })
  })
  it("uses the contract's plural session create and singular session delete", () => {
    expect(apiV1AuthSessions.create()).toEqual({ method: "post", url: "/api/v1/auth/sessions" })
    expect(apiV1AuthSessions.destroy()).toEqual({ method: "delete", url: "/api/v1/auth/session" })
    expect(apiV1SettingsSessions.destroy("device-id")).toEqual({
      method: "delete",
      url: "/api/v1/settings/sessions/device-id",
    })
  })
})
