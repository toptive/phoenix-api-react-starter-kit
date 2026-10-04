import { usePage } from "@inertiajs/react"

import type { SharedProps } from "@/generated/pages"

/** The props every page receives (auth, locale, app…), typed from the server declaration. */
export function useSharedProps(): SharedProps {
  return usePage().props as unknown as SharedProps
}
