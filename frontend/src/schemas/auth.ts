import { z } from "zod"

export const emailSchema = z.string().trim().max(160, "validation.length_max").email("validation.email_format")
export const signInSchema = z.object({ email: emailSchema, password: z.string().min(1, "validation.required") })
export const magicLinkSchema = z.object({ email: emailSchema, turnstileToken: z.string().optional() })
export const registrationSchema = magicLinkSchema.extend({
  name: z.string().trim().min(1, "validation.required").max(120, "validation.length_max"),
  termsAccepted: z.boolean().refine((accepted) => accepted, "validation.terms_required"),
  locale: z.string().optional(),
})
export const sudoSchema = z.object({ password: z.string().min(1, "validation.required") })
export const passwordSchema = z
  .object({
    password: z
      .string()
      .min(12, "validation.length_min")
      .refine((value) => new TextEncoder().encode(value).length <= 72, "validation.length_max"),
    passwordConfirmation: z.string(),
  })
  .refine((values) => values.password === values.passwordConfirmation, {
    path: ["passwordConfirmation"],
    message: "validation.password_mismatch",
  })
export type SignInInput = z.infer<typeof signInSchema>
export type MagicLinkInput = z.infer<typeof magicLinkSchema>
export type RegistrationInput = z.infer<typeof registrationSchema>
export type PasswordInput = z.infer<typeof passwordSchema>
