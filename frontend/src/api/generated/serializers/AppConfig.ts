export interface AppConfig {
  name: string
  tenancy: "multi" | "single"
  signupMode: "open" | "invite" | "closed"
  emailAvailable: boolean
  googleEnabled: boolean
  publicUrl: string
}
