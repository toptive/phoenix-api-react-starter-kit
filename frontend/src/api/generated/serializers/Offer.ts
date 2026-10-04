export interface Offer {
  id: string
  plan: string
  interval: "month" | "year"
  amountCents: number
  currency: string
}
