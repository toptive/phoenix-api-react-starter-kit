import type { User } from "./User"
export interface Membership {
  id: string
  role: "owner" | "admin" | "member"
  access: "full" | "viewer"
  insertedAt: string
  user: User | null
}
