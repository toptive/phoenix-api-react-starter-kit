import { Link } from "@/components/app/link"

import { useAppConfig } from "@/api/hooks/bootstrap"
import { cn } from "@/lib/utils"

/** The product mark + name. Products replace the mark (an SVG using currentColor). */
export function Logo({ href = "/", className }: { href?: string; className?: string }) {
  const { app } = useAppConfig()

  return (
    <Link href={href} className={cn("inline-flex items-center gap-2 font-semibold tracking-tight", className)}>
      <svg viewBox="0 0 24 24" aria-hidden="true" className="size-6 text-primary">
        <rect x="3" y="2.5" width="14" height="19" rx="2.5" fill="currentColor" opacity="0.18" />
        <rect x="7" y="2.5" width="14" height="19" rx="2.5" fill="none" stroke="currentColor" strokeWidth="1.8" />
        <path d="M10.5 12.5l2.2 2.2 4.3-4.6" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
      <span>{app.name}</span>
    </Link>
  )
}
