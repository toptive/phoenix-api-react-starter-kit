export interface AccountDeletion {
  blocker: { reason: "transfer_ownership" | "subscription_active"; organization: string } | null
}
