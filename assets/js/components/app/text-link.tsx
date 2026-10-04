import { Link } from "@inertiajs/react"
import type { ComponentProps } from "react"

import { cn } from "@/lib/utils"

/** An inline link inside text. */
export function TextLink({ className, ...props }: ComponentProps<typeof Link>) {
  return <Link className={cn("font-medium text-primary underline-offset-4 hover:underline", className)} {...props} />
}
