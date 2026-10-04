import { z } from "zod"
import { emailSchema } from "./auth"
import { limits } from "./limits"

export const organizationNameSchema = z
  .string()
  .trim()
  .min(limits.organizationMin, "validation.length_min")
  .max(limits.organizationMax, "validation.length_max")
export const organizationSchema = z.object({ name: organizationNameSchema })
export const onboardingSchema = z.object({
  name: z
    .string()
    .trim()
    .refine((name) => !name || name.length >= limits.organizationMin, "validation.length_min")
    .max(limits.organizationMax, "validation.length_max"),
})
export const membershipSchema = z.object({
  role: z.enum(["owner", "admin", "member"]),
  access: z.enum(["full", "viewer"]),
})
export const invitationSchema = z.object({
  email: emailSchema,
  role: z.enum(["admin", "member"]),
  access: z.enum(["full", "viewer"]),
})
export type OrganizationInput = z.infer<typeof organizationSchema>
export type OnboardingInput = z.infer<typeof onboardingSchema>
export type MembershipInput = z.infer<typeof membershipSchema>
export type InvitationInput = z.infer<typeof invitationSchema>
