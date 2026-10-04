import { useTranslation } from "react-i18next"
import { Button } from "@/components/ui/button"
import { FormError } from "./form-error"

/** Loading and recoverable failures share a visible next step. */
export function QueryState({ pending, error, retry }: { pending: boolean; error: Error | null; retry: () => unknown }) {
  const { t } = useTranslation()
  if (pending)
    return (
      <p role="status" className="py-4">
        {t("common.loading")}
      </p>
    )
  if (!error) return null
  return (
    <div className="grid gap-3 py-4">
      <FormError error={error} />
      <p className="text-sm text-muted-foreground">{t("common.retry_help")}</p>
      <Button
        variant="outline"
        onClick={() => {
          void retry()
        }}
      >
        {t("common.retry")}
      </Button>
    </div>
  )
}
