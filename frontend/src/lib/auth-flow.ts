import { storageKey } from "./storage-keys"
const hasUnsafeCharacters = (value: string) =>
  Array.from(value).some((character) => character === "\\" || character.charCodeAt(0) <= 32)
/** Reject external paths and auth loops before storing or following a return target. */
export function safeReturnPath(raw: unknown): string | null {
  if (
    typeof raw !== "string" ||
    !raw.startsWith("/") ||
    raw.startsWith("//") ||
    hasUnsafeCharacters(raw) ||
    raw.length > 200
  )
    return null
  const path = raw.split(/[?#]/)[0] ?? ""
  if (/^\/(session|registration|magic-links|auth)(\/|$)/.test(path)) return null
  try {
    const decoded = decodeURIComponent(raw)
    if (decoded.startsWith("//") || hasUnsafeCharacters(decoded)) return null
  } catch {
    return null
  }
  return raw
}
export const returnPath = {
  get: () => safeReturnPath(sessionStorage.getItem(storageKey("return-to"))),
  set: (value: unknown) => {
    const path = safeReturnPath(value)
    if (path) sessionStorage.setItem(storageKey("return-to"), path)
    else sessionStorage.removeItem(storageKey("return-to"))
  },
  clear: () => sessionStorage.removeItem(storageKey("return-to")),
}
export function destinationAfterAuth() {
  const path = returnPath.get()
  returnPath.clear()
  return path ?? "/dashboard"
}
