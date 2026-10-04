import { Link } from "@tanstack/react-router"
import type { AnchorHTMLAttributes } from "react"
import { cn } from "@/lib/utils"

/** An internal link with the kit's familiar href prop. */
export function TextLink({ href, className, ...props }: AnchorHTMLAttributes<HTMLAnchorElement> & { href: string }) {
  return (
    <Link
      to={href}
      className={cn("font-medium text-primary underline-offset-4 hover:underline", className)}
      {...props}
    />
  )
}
