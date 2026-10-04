import { InfoIcon } from "lucide-react"
import type { ReactNode } from "react"

import { cn } from "@/lib/utils"

/** Explains a field in place, in plain words. Always visible: users should not hunt for help. */
export function FieldHelp({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <p className={cn("flex gap-1.5 text-sm text-muted-foreground", className)}>
      <InfoIcon aria-hidden="true" className="mt-0.5 size-4 shrink-0" />
      <span>{children}</span>
    </p>
  )
}
