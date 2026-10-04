import { z } from "zod"
import { magicLinkToken } from "@/lib/sudo"
import { limits } from "./limits"

export const emailSchema = z
  .string()
  .trim()
  .max(limits.emailMax, "validation.length_max")
  .email("validation.email_format")
export const signInSchema = z.object({ email: emailSchema, password: z.string().min(1, "validation.required") })
export const magicLinkSchema = z.object({ email: emailSchema, turnstileToken: z.string().optional() })
export const registrationSchema = magicLinkSchema.extend({
  name: z.string().trim().min(1, "validation.required").max(limits.nameMax, "validation.length_max"),
  termsAccepted: z.boolean().refine((accepted) => accepted, "validation.terms_required"),
  locale: z.string().optional(),
})
export const sudoSchema = z.object({ password: z.string().min(1, "validation.required") })
export type SignInInput = z.infer<typeof signInSchema>
export type MagicLinkInput = z.infer<typeof magicLinkSchema>
export type RegistrationInput = z.infer<typeof registrationSchema>

export const sudoLinkSchema = z.object({
  link: z.string().refine((value) => Boolean(magicLinkToken(value)), "validation.magic_link"),
})
