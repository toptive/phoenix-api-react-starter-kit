import { Link as RouterLink } from "@tanstack/react-router"
import type { AnchorHTMLAttributes } from "react"
/** Shared internal navigation keeps links accessible and preserves browser modifiers. */
export function Link({ href, ...props }: AnchorHTMLAttributes<HTMLAnchorElement> & { href: string }) {
  return <RouterLink to={href} {...props} />
}
