import type { ReactNode } from "react"
import { useId } from "react"

import { FieldHelp } from "@/components/app/field-help"
import { Label } from "@/components/ui/label"
import { cn } from "@/lib/utils"

type Props = {
  label: string
  help?: ReactNode
  error?: string
  className?: string
  children: (id: string, describedBy: string | undefined) => ReactNode
}

/**
 * Label + control + help + error, wired for screen readers.
 *
 *   <FormField label={t("…")} help={t("…")} error={form.errors.email}>
 *     {(id, describedBy) => <Input id={id} aria-describedby={describedBy} … />}
 *   </FormField>
 */
export function FormField({ label, help, error, className, children }: Props) {
  const id = useId()
  const helpId = `${id}-help`
  const errorId = `${id}-error`
  const describedBy = [help ? helpId : null, error ? errorId : null].filter(Boolean).join(" ") || undefined

  return (
    <div className={cn("grid gap-2", className)}>
      <Label htmlFor={id}>{label}</Label>
      {children(id, describedBy)}
      {help && <div id={helpId}><FieldHelp>{help}</FieldHelp></div>}
      {error && (
        <p id={errorId} role="alert" className="text-sm font-medium text-destructive">
          {error}
        </p>
      )}
    </div>
  )
}
