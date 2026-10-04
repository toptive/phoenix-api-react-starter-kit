import type { User } from "./User"
import type { Organization } from "./Organization"
export interface AdminUserDetail {
  user: User
  organizations: Organization[]
}
