import { ApiError } from "@/api/http"

/** Retry once, only after a successful confirmation; unrelated refusals pass through. */
export async function withSudoConfirmation<T>(action: () => Promise<T>, confirm: () => Promise<void>): Promise<T> {
  try {
    return await action()
  } catch (error) {
    if (!(error instanceof ApiError) || error.status !== 403 || error.code !== "sudo_required") throw error
    await confirm()
    return action()
  }
}
/** Accept the emailed link or its opaque token without sending the link's origin anywhere. */
export function magicLinkToken(value: string): string | null {
  const trimmed = value.trim()
  if (/^[A-Za-z0-9_-]+$/.test(trimmed)) return trimmed
  try {
    const url = new URL(trimmed)
    const match = /^\/magic-links\/([A-Za-z0-9_-]+)\/?$/.exec(url.pathname)
    return ["http:", "https:"].includes(url.protocol) ? (match?.[1] ?? null) : null
  } catch {
    return null
  }
}
