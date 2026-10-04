export const stripeStubConfig: {
  url: string
  secret: string
  offers: {
    id: string
    priceId: string
    amountCents: number
    currency: string
    interval: "month" | "year"
  }[]
}
export function startStripeStub(): Promise<() => Promise<void>>
