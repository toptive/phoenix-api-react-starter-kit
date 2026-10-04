import { describe, expect, it } from "vitest"
import { describeDevice } from "./device"

describe("device description", () => {
  it("prefers Edge over its Chrome compatibility marker", () =>
    expect(describeDevice("Windows Chrome/120 Edg/120")).toBe("Edge · Windows"))
  it("recognises mobile agents and uses a fallback for unknown agents", () => {
    expect(describeDevice("iPhone Safari/604")).toBe("Safari · iOS")
    expect(describeDevice("Android Chrome/120")).toBe("Chrome · Android")
    expect(describeDevice(null)).toBeNull()
    expect(describeDevice("unknown")).toBeNull()
  })
})
