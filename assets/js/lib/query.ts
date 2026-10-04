/** Drops empty query values so URLs stay clean: { q: "", page: 2 } → { page: 2 }. */
export function compact(query: Record<string, string | number | null | undefined>): Record<string, string | number> {
  const out: Record<string, string | number> = {}
  for (const [key, value] of Object.entries(query)) {
    if (value !== null && value !== undefined && value !== "") out[key] = value
  }
  return out
}
