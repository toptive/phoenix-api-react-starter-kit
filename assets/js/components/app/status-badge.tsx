import { Badge } from "@/components/ui/badge"
import { cn } from "@/lib/utils"

const tones = {
  neutral: "bg-muted text-muted-foreground",
  success: "bg-success/12 text-success",
  warning: "bg-warning/15 text-warning",
  danger: "bg-destructive/12 text-destructive",
  info: "bg-info/12 text-info",
}

/** A small coloured label for a state (role, access, published, pending…). */
export function StatusBadge({ tone = "neutral", children }: { tone?: keyof typeof tones; children: string }) {
  return (
    <Badge variant="secondary" className={cn("border-transparent font-medium", tones[tone])}>
      {children}
    </Badge>
  )
}
