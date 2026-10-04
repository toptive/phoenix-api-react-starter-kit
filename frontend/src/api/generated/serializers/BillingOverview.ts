import type { Subscription } from "./Subscription"
import type { Offer } from "./Offer"
export interface BillingOverview {
  plan: string
  subscription: Subscription | null
  offers: Offer[]
  offerRevision: string
  sales: "open" | "test" | "closed"
  canManage: boolean
}
