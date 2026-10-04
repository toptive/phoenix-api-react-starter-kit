import type { User } from "./User"
import type { Organization } from "./Organization"
import type { Membership } from "./Membership"
export interface Auth {
  user: User
  organization: Organization
  membership: Membership
  organizations: Organization[]
  superadmin: boolean
  impersonator: User | null
  onboardingRequired: boolean
  sudoUntil: string | null
  sessionId: string
}
