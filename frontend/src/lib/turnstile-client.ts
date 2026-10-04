export type TurnstileApi = {
  render: (
    container: HTMLElement,
    options: {
      sitekey: string
      action: string
      theme: "light" | "dark" | "auto"
      size: "flexible"
      appearance: "interaction-only"
      language: string
      callback: (token: string) => void
      "expired-callback": () => void
      "error-callback": () => void
    },
  ) => string
  remove: (id: string) => void
}
declare global {
  interface Window {
    turnstile?: TurnstileApi
  }
}
let loading: Promise<TurnstileApi> | undefined

export function loadWidget() {
  if (window.turnstile) return Promise.resolve(window.turnstile)
  loading ??= new Promise<TurnstileApi>((resolve, reject) => {
    const script = document.createElement("script")
    script.src = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"
    script.async = true
    const timer = setTimeout(() => {
      script.remove()
      reject(new Error("verification_unavailable"))
    }, 15_000)
    script.onload = () => {
      clearTimeout(timer)
      if (window.turnstile) resolve(window.turnstile)
      else {
        script.remove()
        reject(new Error("verification_unavailable"))
      }
    }
    script.onerror = () => {
      clearTimeout(timer)
      script.remove()
      reject(new Error("verification_unavailable"))
    }
    document.head.append(script)
  }).catch((error: unknown) => {
    loading = undefined
    throw error
  })
  return loading
}

