import type { ListSearch } from "@/schemas/search"
/** Preserve search and page size while resetting the page for changed filters. */
export function listHref(
  path: string,
  search: ListSearch & { missing?: string },
  changes: Partial<ListSearch & { missing: string }> = {},
) {
  const next = { ...search, ...changes }
  if (changes.q !== undefined || changes.missing !== undefined || changes.perPage !== undefined) next.page = 1
  const query = new URLSearchParams()
  Object.entries(next).forEach(([key, value]) => {
    if (value !== undefined && value !== "") query.set(key, String(value))
  })
  return `${path}?${query}`
}

/** Pass search separately so the router validates the destination parameters. */
export function listNavigation(href: string) {
  const url = new URL(href, window.location.origin)
  return { to: url.pathname, search: Object.fromEntries(url.searchParams) }
}
