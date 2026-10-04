import type { FieldValues, Path, UseFormSetError } from "react-hook-form"
import { ApiError } from "@/api/http"
import type { FieldError } from "@/api/generated/serializers"
import { i18n } from "@/i18n"

export function applyFormErrors<T extends FieldValues>(error: unknown, setError: UseFormSetError<T>) {
  if (error instanceof ApiError && ["validation_failed", "turnstile_failed"].includes(error.code)) {
    let focus = true
    for (const [field, value] of Object.entries(error.details)) {
      if (!Array.isArray(value)) continue
      const issue = value[0] as FieldError | undefined
      if (issue) {
        setError(
          field as Path<T>,
          { type: "server", message: i18n.t(issue.key, { ...issue.bindings, defaultValue: issue.message }) },
          { shouldFocus: focus },
        )
        focus = false
      }
    }
  } else {
    setError("root", {
      type: "server",
      message: error instanceof ApiError ? error.message : i18n.t("errors.api.internal_error"),
    })
  }
}
/** Zod stores keys; server messages are already translated with their bindings. */
export const fieldMessage = (message?: string, maximum = 160) =>
  message
    ? i18n.t(message, { count: message === "validation.length_min" ? 12 : maximum, defaultValue: message })
    : undefined
