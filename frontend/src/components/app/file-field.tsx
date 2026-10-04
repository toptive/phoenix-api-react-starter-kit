import { useState } from "react"
import { useTranslation } from "react-i18next"
import { LoaderCircleIcon } from "lucide-react"
import { useDirectUpload } from "@/api/hooks/uploads"
import { UploadError, type UploadKind } from "@/api/uploads"
import { FormField } from "./form-field"
import { Input } from "@/components/ui/input"

const accepted = {
  image: "image/jpeg,image/png,image/webp,image/gif",
  document: "application/pdf,image/jpeg,image/png",
  avatar: "image/jpeg,image/png,image/webp",
}
/** The returned key is attached by the owning form, after the storage PUT completes. */
export function FileField({
  kind,
  value,
  label,
  help,
  error,
  disabled,
  onChange,
  onBusyChange,
}: {
  kind: UploadKind
  value: string | undefined
  label: string
  help?: string
  error?: string
  disabled?: boolean
  onChange: (key: string) => void
  onBusyChange?: (busy: boolean) => void
}) {
  const { t } = useTranslation()
  const upload = useDirectUpload(kind)
  const [filename, setFilename] = useState("")
  const uploadError =
    upload.error instanceof UploadError
      ? t(`errors.api.${upload.error.code}`, { defaultValue: upload.error.message })
      : upload.error
        ? t("errors.network")
        : undefined
  return (
    <div className="space-y-2">
      <FormField label={label} help={help} error={error ?? uploadError}>
        {(id, describedBy) => (
          <Input
            id={id}
            aria-describedby={describedBy}
            aria-busy={upload.isPending}
            type="file"
            accept={accepted[kind]}
            disabled={disabled || upload.isPending}
            onChange={(event) => {
              const file = event.target.files?.[0]
              event.target.value = ""
              if (!file) return
              onBusyChange?.(true)
              setFilename("")
              upload.mutate(file, {
                onSuccess: (key) => {
                  setFilename(file.name)
                  onChange(key)
                },
                onSettled: () => onBusyChange?.(false),
              })
            }}
          />
        )}
      </FormField>
      {upload.isPending && (
        <p role="status" className="flex items-center gap-2 text-sm text-muted-foreground">
          <LoaderCircleIcon aria-hidden="true" className="size-4 animate-spin motion-reduce:animate-none" />
          {t("uploads.uploading")}
        </p>
      )}
      {value && filename && (
        <p role="status" className="text-sm text-muted-foreground">
          {t("uploads.ready", { filename })}
        </p>
      )}
    </div>
  )
}
