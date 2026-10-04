export interface InvitationPreview {
  organization: string
  email: string
  role: "owner" | "admin" | "member"
  access: "full" | "viewer"
  emailMatches: boolean
  expiresAt: string
}
