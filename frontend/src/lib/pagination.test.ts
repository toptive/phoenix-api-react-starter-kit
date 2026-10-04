import { describe, expect, it } from "vitest"
import { listHref } from "./pagination"
const search = { q: "Ana & team", page: 4, perPage: 50, locale: "es", missing: "es" }
describe("list links", () => {
  it("preserves filters, locale and page size when moving pages", () => {
    const url = new URL(listHref("/admin/translations", search, { page: 5 }), "https://app.example.com")
    expect(Object.fromEntries(url.searchParams)).toEqual({
      q: "Ana & team",
      page: "5",
      perPage: "50",
      locale: "es",
      missing: "es",
    })
  })
  it("resets the page on search, page size or missing-locale changes", () => {
    for (const change of [{ q: "Bob" }, { perPage: 25 }, { missing: "en" }])
      expect(
        new URL(listHref("/admin/translations", search, change), "https://app.example.com").searchParams.get("page"),
      ).toBe("1")
  })
  it("removes empty filters without discarding pagination", () => {
    const url = new URL(listHref("/admin/translations", search, { q: "", missing: "" }), "https://app.example.com")
    expect(url.searchParams.has("q")).toBe(false)
    expect(url.searchParams.has("missing")).toBe(false)
    expect(url.searchParams.get("perPage")).toBe("50")
  })
})
