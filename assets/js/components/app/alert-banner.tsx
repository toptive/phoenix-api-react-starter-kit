import { AlertTriangleIcon, CheckCircle2Icon, InfoIcon, OctagonAlertIcon } from "lucide-react"
import type { ReactNode } from "react"

import { cn } from "@/lib/utils"

const tones = {
  info: { icon: InfoIcon, className: "border-info/30 bg-info/10 text-foreground [&_svg]:text-info" },
  success: { icon: CheckCircle2Icon, className: "border-success/30 bg-success/10 text-foreground [&_svg]:text-success" },
  warning: { icon: AlertTriangleIcon, className: "border-warning/40 bg-warning/10 text-foreground [&_svg]:text-warning" },
  danger: { icon: OctagonAlertIcon, className: "border-destructive/30 bg-destructive/10 text-foreground [&_svg]:text-destructive" },
}

/** A state explanation with the next step. Say what happened and what to do. */
export function AlertBanner({
  tone = "info",
  title,
  children,
  action,
  className,
}: {
  tone?: keyof typeof tones
  title: string
  children?: ReactNode
  action?: ReactNode
  className?: string
}) {
  const { icon: Icon, className: toneClass } = tones[tone]

  return (
    <div role={tone === "danger" ? "alert" : "status"} className={cn("flex gap-3 rounded-xl border p-4", toneClass, className)}>
      <Icon aria-hidden="true" className="mt-0.5 size-5 shrink-0" />
      <div className="flex-1 space-y-1">
        <p className="font-semibold">{title}</p>
        {children && <div className="text-sm text-muted-foreground">{children}</div>}
        {action && <div className="pt-2">{action}</div>}
      </div>
    </div>
  )
}
