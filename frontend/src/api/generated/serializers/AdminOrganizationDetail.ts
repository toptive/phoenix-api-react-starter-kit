import type { Organization } from "./Organization"
import type { Membership } from "./Membership"
export interface AdminOrganizationDetail {
  organization: Organization
  memberships: Membership[]
}
