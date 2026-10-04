import { z } from "zod"
import { emailSchema } from "./auth"
import { limits } from "./limits"

export const profileSchema = (locales: string[]) =>
  z.object({
    name: z.string().trim().min(1, "validation.required").max(limits.nameMax, "validation.length_max"),
    locale: z.string().refine((locale) => locales.includes(locale), "validation.inclusion"),
  })
export const emailPreferencesSchema = z.object({ optionalEmails: z.boolean() })
export const changeEmailSchema = z.object({ email: emailSchema })
export const passwordSchema = z
  .object({
    password: z
      .string()
      .min(limits.passwordMin, "validation.length_min")
      .refine((value) => new TextEncoder().encode(value).length <= limits.passwordMaxBytes, "validation.length_max"),
    passwordConfirmation: z.string(),
  })
  .refine((values) => values.password === values.passwordConfirmation, {
    path: ["passwordConfirmation"],
    message: "validation.password_mismatch",
  })
export type ProfileInput = z.infer<ReturnType<typeof profileSchema>>
export type EmailPreferencesInput = z.infer<typeof emailPreferencesSchema>
export type ChangeEmailInput = z.infer<typeof changeEmailSchema>
export type PasswordInput = z.infer<typeof passwordSchema>
