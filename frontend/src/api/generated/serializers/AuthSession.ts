import type { User } from "./User"
export interface AuthSession {
  token: string | null
  expiresAt: string
  sudoUntil: string | null
  user: User
  impersonator: User | null
  newAccount: boolean
}
