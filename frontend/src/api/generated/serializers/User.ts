export interface User {
  id: string
  name: string
  email: string
  role: "user" | "superadmin"
  locale: string
  confirmedAt: string | null
  insertedAt: string
  hasPassword: boolean
}
