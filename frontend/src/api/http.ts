import { toast } from "sonner"
import { i18n } from "@/i18n"
import { reportApiFailure } from "@/lib/api-failure"
import { storageKey } from "@/lib/storage-keys"
import type { ApiErrorBody, Envelope as GeneratedEnvelope, Pagination } from "./generated/serializers"
import { setBaseUrl, type Method, type RouteDefinition } from "./generated/routes/runtime"

type Envelope<T> = GeneratedEnvelope<T, { pagination?: Pagination } & Record<string, unknown>>

export const TOKEN_KEY = storageKey("token")
export const ADMIN_TOKEN_KEY = storageKey("admin-token")
export const getToken = (): string | null =>
  typeof localStorage === "undefined" ? null : localStorage.getItem(TOKEN_KEY)
export const setToken = (token: string) => localStorage.setItem(TOKEN_KEY, token)
export const clearToken = () => localStorage.removeItem(TOKEN_KEY)
export const clearTokens = () => {
  clearToken()
  localStorage.removeItem(ADMIN_TOKEN_KEY)
}

let origin = ""
export function configureApi(value: string) {
  origin = value.replace(/\/+$/, "").replace(/\/api\/v1$/, "")
  setBaseUrl(origin)
}
configureApi(import.meta.env.VITE_API_URL ?? "")

export class ApiError extends Error {
  readonly status: number
  readonly code: string
  readonly details: Record<string, unknown>
  constructor(body: ApiErrorBody, status: number) {
    super(body.message)
    this.name = "ApiError"
    this.status = status
    this.code = body.code
    this.details = body.details
  }
}

let onUnauthorized: (() => void) | undefined
export function setUnauthorizedHandler(handler?: () => void) {
  onUnauthorized = handler
}

function sessionExpired() {
  clearTokens()
  if (onUnauthorized) onUnauthorized()
  else if (typeof window !== "undefined") {
    const returnTo = window.location.pathname + window.location.search
    window.location.assign(`/session/new?returnTo=${encodeURIComponent(returnTo)}`)
  }
}

type RequestOptions = { headers?: Record<string, string>; signal?: AbortSignal; anonymous?: boolean }
export async function request<T>(
  route: RouteDefinition<Method>,
  body?: unknown,
  options: RequestOptions = {},
): Promise<Envelope<T>> {
  const token = options.anonymous ? null : getToken()
  const headers: Record<string, string> = {
    Accept: "application/json",
    "Accept-Language": i18n.language,
    ...options.headers,
  }
  if (body !== undefined) headers["Content-Type"] = "application/json"
  if (token) headers.Authorization = `Bearer ${token}`
  let response: Response
  try {
    response = await fetch(route.url.startsWith("/") ? origin + route.url : route.url, {
      method: route.method.toUpperCase(),
      headers,
      signal: options.signal,
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    })
  } catch (error) {
    if (!options.signal?.aborted) {
      toast.error(i18n.t(typeof navigator !== "undefined" && !navigator.onLine ? "errors.offline" : "errors.network"), {
        id: "network-status",
      })
    }
    throw error
  }
  if (response.status === 204 || response.status === 304) return { data: undefined as T }
  let payload: { error?: ApiErrorBody } & Partial<Envelope<T>> = {}
  try {
    payload = await response.json()
  } catch {
    /* Map malformed error responses to the same error type. */
  }
  if (!response.ok) {
    const error = new ApiError(
      payload.error ?? { code: "internal_error", message: i18n.t("errors.api.internal_error"), details: {} },
      response.status,
    )
    if (
      response.status === 401 &&
      token &&
      getToken() === token &&
      ["unauthorized", "session_expired"].includes(error.code)
    )
      sessionExpired()
    if (response.status === 429) {
      const seconds = Number(response.headers.get("Retry-After"))
      toast.error(error.message, {
        ...(seconds > 0 ? { description: i18n.t("errors.retry_after", { count: seconds }) } : {}),
      })
    }
    if (
      ![
        "sudo_required",
        "email_unavailable",
        "ai_not_configured",
        "ai_unavailable",
        "uploads_not_configured",
        "stripe_unavailable",
        "test_mode",
      ].includes(error.code)
    )
      reportApiFailure(response.status)
    throw error
  }
  if (!("data" in payload))
    throw new ApiError(
      { code: "internal_error", message: i18n.t("errors.api.internal_error"), details: {} },
      response.status,
    )
  return payload as Envelope<T>
}

/** Keep the envelope available for paginated lists; hooks unwrap its data. */
export const api = {
  get: <T>(route: RouteDefinition<"get">, options?: RequestOptions) => request<T>(route, undefined, options),
  post: <T>(route: RouteDefinition<"post">, body: unknown = {}, options?: RequestOptions) =>
    request<T>(route, body, options),
  put: <T>(route: RouteDefinition<"put">, body: unknown, options?: RequestOptions) => request<T>(route, body, options),
  del: <T = void>(route: RouteDefinition<"delete">) => request<T>(route),
}
