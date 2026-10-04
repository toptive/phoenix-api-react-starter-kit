import { useTranslation } from "react-i18next"
import { ApiError } from "@/api/http"
export function FormError({ message, error }: { message?: string; error?: Error | null }) {
  const { t } = useTranslation()
  const text = message ?? (error instanceof ApiError ? error.message : error ? t("errors.api.internal_error") : null)
  return text ? (
    <p role="alert" className="text-sm font-medium text-destructive">
      {text}
    </p>
  ) : null
}
