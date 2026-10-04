import { useEffect, useRef, useState } from "react"
import { useTranslation } from "react-i18next"

import { Button } from "@/components/ui/button"
import { useAppearance } from "@/hooks/use-appearance"
import { useAppConfig } from "@/api/hooks/bootstrap"
import { loadWidget, type TurnstileApi } from "@/lib/turnstile-client"

/** Form action names verified by the API. */
export type TurnstileAction = "registration" | "magic_link"

/**
 * Cloudflare Turnstile for forms protected by the API. Renders nothing while
 * protection is off (`turnstile.required`). Tokens are single-use: bump `attempt` after
 * every submit so a fresh widget gives a new token. `onToken` must be stable (useCallback).
 * The effect only mounts the third-party widget; it never loads data.
 */
export function Turnstile({ action, attempt, error, onToken }: {
  action: TurnstileAction
  attempt: number
  error?: string
  onToken: (token: string) => void
}) {
  const { t, i18n } = useTranslation()
  const { turnstile } = useAppConfig()
  const { appearance } = useAppearance()
  const container = useRef<HTMLDivElement>(null)
  const [failed, setFailed] = useState(false)
  const [retry, setRetry] = useState(0)

  useEffect(() => {
    if (!turnstile.required) return
    let disposed = false
    let widget: string | undefined
    let api: TurnstileApi | undefined
    const fail = () => {
      if (!disposed) {
        onToken("")
        setFailed(true)
      }
    }
    onToken("")
    const siteKey = turnstile.siteKey
    if (!siteKey) return

    void loadWidget().then((loaded) => {
      if (disposed || !container.current) return
      api = loaded
      widget = loaded.render(container.current, {
        sitekey: siteKey,
        action,
        theme: appearance === "system" ? "auto" : appearance,
        size: "flexible",
        appearance: "interaction-only",
        language: i18n.language,
        callback: (token) => {
          if (!disposed) {
            setFailed(false)
            onToken(token)
          }
        },
        "expired-callback": () => { if (!disposed) onToken("") },
        "error-callback": fail,
      })
    }).catch(fail)

    return () => {
      disposed = true
      if (widget) api?.remove(widget)
    }
  }, [turnstile.required, turnstile.siteKey, action, attempt, retry, appearance, i18n.language, onToken])

  if (!turnstile.required) return null

  return (
    <div className="min-w-0 space-y-2">
      <div ref={container} data-turnstile={action} role="group" aria-label={t("auth.verification.label")} />
      {error && <p role="alert" className="text-sm font-medium text-destructive">{error}</p>}
      {(failed || !turnstile.siteKey) && (
        <div role="status" className="space-y-2 text-sm">
          <p>{t("auth.verification.unavailable")}</p>
          <Button type="button" variant="outline" className="min-h-11" onClick={() => { setFailed(false); setRetry((value) => value + 1) }}>
            {t("auth.verification.retry")}
          </Button>
        </div>
      )}
    </div>
  )
}
