import { z } from "zod"
export const checkoutSchema = z.object({
  offerId: z.string().min(1, "validation.required"),
  offerRevision: z.string(),
  accepted: z.boolean().refine((accepted) => accepted, "billing.checkout.not_accepted"),
})
export type CheckoutInput = z.infer<typeof checkoutSchema>
