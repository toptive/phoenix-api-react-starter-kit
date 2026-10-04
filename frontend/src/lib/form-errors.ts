import type { FieldValues, Path, UseFormSetError } from "react-hook-form"
import { ApiError } from "@/api/http"
import type { FieldError } from "@/api/generated/serializers"
import { i18n } from "@/i18n"

/** Server messages already include the requested locale and interpolation bindings. */
export function validationMessages(details: Record<string, unknown>): Record<string, string> {
  return Object.fromEntries(
    Object.entries(details).flatMap(([field, value]) => {
      if (!Array.isArray(value)) return []
      const issue = value[0] as FieldError | undefined
      return issue && typeof issue.message === "string" ? [[field, issue.message]] : []
    }),
  )
}
export function applyFormErrors<T extends FieldValues>(error: unknown, setError: UseFormSetError<T>) {
  const messages =
    error instanceof ApiError && ["validation_failed", "turnstile_failed"].includes(error.code)
      ? validationMessages(error.details)
      : {}
  const entries = Object.entries(messages)
  if (entries.length) {
    entries.forEach(([field, message], index) =>
      setError(field as Path<T>, { type: "server", message }, { shouldFocus: index === 0 }),
    )
  } else {
    setError("root", {
      type: "server",
      message: error instanceof ApiError ? error.message : i18n.t("errors.api.internal_error"),
    })
  }
}
/** Only client-side keys need translating here; server field messages pass through. */
export const fieldMessage = (
  message?: string,
  bindings: Record<string, string | number> = {},
) => (message ? i18n.t(message, { ...bindings, defaultValue: message }) : undefined)

export const boundedFieldMessage = (message: string | undefined, minimum: number, maximum: number) =>
  fieldMessage(message, { count: message === "validation.length_min" ? minimum : maximum })
