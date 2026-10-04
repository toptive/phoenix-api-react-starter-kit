import { describe, expect, it } from "vitest"

import { formatDate, formatDateTime, formatMoney, initials } from "@/lib/format"
import { compact } from "@/lib/query"

describe("format", () => {
  it("builds initials from one or more names", () => {
    expect(initials("Ana María López")).toBe("AL")
    expect(initials("ana@example.com")).toBe("A")
  })

  it("formats money stored as integer cents", () => {
    expect(formatMoney(1250, "EUR", "en")).toContain("12.50")
    expect(formatMoney(1250, "EUR", "es")).toContain("12,50")
  })

  it("formats ISO dates for people and tolerates null", () => {
    expect(formatDate("2026-09-30T10:00:00Z", "en")).toContain("2026")
    expect(formatDate(null, "en")).toBe("")
  })

  it("puts the day first in English and reads dates in UTC", () => {
    expect(formatDate("2026-09-30T10:00:00Z", "en")).toMatch(/^30 Sept? 2026$/)
    // 23:30 UTC is already the next day east of UTC: the date must not move.
    expect(formatDate("2026-09-30T23:30:00Z", "en")).toMatch(/^30 /)
    expect(formatDate("2026-09-30T23:30:00Z", "es")).toMatch(/^30 /)
  })

  it("shows the zone with date and time", () => {
    expect(formatDateTime("2026-09-30T14:05:00Z", "en")).toMatch(/^30 .*2026.*14:05:00 UTC$/)
    expect(formatDateTime(undefined, "en")).toBe("")
  })

  it("drops empty query values", () => {
    expect(compact({ q: "ana", page: 2, missing: "", other: null })).toEqual({ q: "ana", page: 2 })
  })
})
