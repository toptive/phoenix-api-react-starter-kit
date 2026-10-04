export interface AppConfig {
  name: string
  tenancy: "multi" | "single"
  signupMode: "open" | "invite" | "closed"
  emailAvailable: boolean
  jobsDashboard: boolean
  googleEnabled: boolean
  publicUrl: string
}
