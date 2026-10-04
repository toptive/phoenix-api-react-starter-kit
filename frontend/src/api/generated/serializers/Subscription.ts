export interface Subscription {
  plan: string
  offerId: string | null
  status: string
  currentPeriodEnd: string | null
  cancelAtPeriodEnd: boolean
  paused: boolean
  paid: boolean
}
