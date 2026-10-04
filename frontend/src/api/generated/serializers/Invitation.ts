export interface Invitation {
  id: string
  email: string
  role: "owner" | "admin" | "member"
  access: "full" | "viewer"
  expiresAt: string
  insertedAt: string
}
