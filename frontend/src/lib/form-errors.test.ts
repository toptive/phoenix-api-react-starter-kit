import { describe, expect, it, vi } from "vitest"
import { applyFormErrors, fieldMessage, validationMessages } from "./form-errors"
import { ApiError } from "@/api/http"
import { i18n } from "@/i18n"

describe("validation messages", () => {
  it("keeps server messages and ignores malformed details", () => {
    expect(
      validationMessages({
        name: [{ key: "validation.length_min", message: "Use 2 characters.", bindings: { count: 2 } }],
        empty: [],
        other: "bad",
      }),
    ).toEqual({ name: "Use 2 characters." })
  })
  it("maps camelCase fields and focuses only the first failure", () => {
    const setError = vi.fn()
    applyFormErrors(
      new ApiError(
        {
          code: "validation_failed",
          message: "Fix the form",
          details: {
            password: [{ key: "validation.length_max", message: "At most 72 bytes.", bindings: { count: 72 } }],
            passwordConfirmation: [{ key: "validation.password_mismatch", message: "Passwords differ." }],
          },
        },
        422,
      ),
      setError,
    )
    expect(setError).toHaveBeenCalledWith(
      "password",
      { type: "server", message: "At most 72 bytes." },
      { shouldFocus: true },
    )
    expect(setError).toHaveBeenCalledWith(
      "passwordConfirmation",
      { type: "server", message: "Passwords differ." },
      { shouldFocus: false },
    )
  })
  it("falls back to a form error when details contain no fields", () => {
    const setError = vi.fn()
    applyFormErrors(new ApiError({ code: "validation_failed", message: "Try again", details: {} }, 422), setError)
    expect(setError).toHaveBeenCalledWith("root", { type: "server", message: "Try again" })
  })
  it("interpolates client bounds separately for minimum and maximum", () => {
    void i18n.changeLanguage("en")
    expect(fieldMessage("validation.length_min", { count: 2 })).toContain("2")
    expect(fieldMessage("validation.length_max", { count: 80 })).toContain("80")
  })
})
