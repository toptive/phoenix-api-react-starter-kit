import type { Auth } from "./Auth"
import type { AppConfig } from "./AppConfig"
import type { Flags } from "./Flags"
import type { Turnstile } from "./Turnstile"
export interface Bootstrap {
  auth: Auth | null
  locale: string
  locales: string[]
  i18nVersion: string
  app: AppConfig
  flags: Flags
  turnstile: Turnstile
}
