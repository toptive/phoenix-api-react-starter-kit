import { beforeEach, describe, expect, it } from "vitest"
import { listSearchSchema, translationSearchSchema, billingSearchSchema, setSearchLocales } from "./search"
describe("route search parameters", () => {
  beforeEach(() => setSearchLocales(["en", "es"]))
  it("uses bootstrap locales beyond the bundled catalogue", () => {
    setSearchLocales(["en", "fr"])
    expect(translationSearchSchema.parse({ missing: "fr", locale: "fr" })).toMatchObject({
      missing: "fr",
      locale: "fr",
    })
    expect(translationSearchSchema.parse({ missing: "es" }).missing).toBeUndefined()
  })
  it("defaults, trims and drops parameters that do not belong to the route", () => {
    expect(listSearchSchema.parse({ q: "  Ana  ", missing: "es", unexpected: true })).toEqual({
      q: "Ana",
      page: 1,
      perPage: 25,
    })
  })
  it("clamps and floors pagination bounds, including zero", () => {
    expect(listSearchSchema.parse({ page: "2000000", perPage: "0" })).toMatchObject({ page: 1_000_000, perPage: 1 })
    expect(listSearchSchema.parse({ page: -5, perPage: 125 })).toMatchObject({ page: 1, perPage: 100 })
    expect(listSearchSchema.parse({ page: "2.9", perPage: "30.4" })).toMatchObject({ page: 2, perPage: 30 })
  })
  it("recovers from malformed pagination without NaN or Infinity", () => {
    expect(listSearchSchema.parse({ page: "invalid", perPage: Infinity })).toMatchObject({ page: 1, perPage: 25 })
    expect(listSearchSchema.parse({ page: true, perPage: null, q: {} })).toEqual({ page: 1, perPage: 25, q: "" })
  })
  it("accepts supported locale codes for missing texts, never booleans", () => {
    expect(translationSearchSchema.parse({ missing: "es" }).missing).toBe("es")
    for (const missing of [true, "true", "1", "fr"])
      expect(translationSearchSchema.parse({ missing }).missing).toBeUndefined()
  })
  it("keeps only the supported billing return marker and locale", () => {
    expect(billingSearchSchema.parse({ checkout: "done", locale: "es", page: 2 })).toEqual({
      checkout: "done",
      locale: "es",
    })
    expect(billingSearchSchema.parse({ checkout: "other", locale: "bad" })).toEqual({
      checkout: undefined,
      locale: undefined,
    })
  })
})
