import { describe, expect, it, vi } from "vitest"
import { ApiError } from "@/api/http"
import { magicLinkToken, withSudoConfirmation } from "./sudo"

const required = () => new ApiError({ code: "sudo_required", message: "Confirm", details: {} }, 403)
describe("sudo retry", () => {
  it("waits for confirmation before retrying the original action", async () => {
    const order: string[] = []
    const action = vi
      .fn()
      .mockImplementationOnce(async () => {
        order.push("action")
        throw required()
      })
      .mockImplementationOnce(async () => {
        order.push("retry")
        return "saved"
      })
    const confirm = vi.fn(async () => {
      order.push("confirm")
    })
    expect(await withSudoConfirmation(action, confirm)).toBe("saved")
    expect(order).toEqual(["action", "confirm", "retry"])
  })
  it("never retries on cancellation, other refusals or repeated sudo failure", async () => {
    const cancelled = vi.fn(async () => {
      throw new Error("Cancelled")
    })
    const action = vi.fn(async () => {
      throw required()
    })
    await expect(withSudoConfirmation(action, cancelled)).rejects.toThrow("Cancelled")
    expect(action).toHaveBeenCalledOnce()
    const confirm = vi.fn(async () => {})
    const forbidden = new ApiError({ code: "forbidden", message: "Forbidden", details: {} }, 403)
    await expect(
      withSudoConfirmation(async () => {
        throw forbidden
      }, confirm),
    ).rejects.toBe(forbidden)
    expect(confirm).not.toHaveBeenCalled()
    action.mockClear()
    await expect(withSudoConfirmation(action, confirm)).rejects.toMatchObject({ code: "sudo_required" })
    expect(action).toHaveBeenCalledTimes(2)
    expect(confirm).toHaveBeenCalledOnce()
  })
  it("passes through successful actions without asking for confirmation", async () => {
    const confirm = vi.fn(async () => {})
    expect(await withSudoConfirmation(async () => 42, confirm)).toBe(42)
    expect(confirm).not.toHaveBeenCalled()
  })
})
describe("email link parsing", () => {
  it("accepts a link or a token and ignores the link's query", () => {
    expect(magicLinkToken(" https://app.example.com/magic-links/token_123-abc?locale=es ")).toBe("token_123-abc")
    expect(magicLinkToken("token_123-abc")).toBe("token_123-abc")
  })
  it("rejects other routes, malformed URLs and executable links", () => {
    for (const value of [
      "",
      "not a token",
      "javascript:alert(1)",
      "https://app.example.com/settings/email",
      "https://app.example.com/magic-links/a/b",
    ])
      expect(magicLinkToken(value)).toBeNull()
  })
})
