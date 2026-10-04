import { z } from "zod"
export const impersonationSchema = z.object({
  reason: z.string().trim().min(5, "validation.length_min").max(255, "validation.length_max"),
})
export const translationSchema = z.object({
  locale: z.string(),
  value: z.string().max(20_000, "validation.length_max"),
})
export const legalVersionSchema = z.object({
  titles: z
    .record(z.string(), z.string())
    .refine((values) => Boolean(values.en?.trim()), "validation.english_required"),
  bodies: z
    .record(z.string(), z.string())
    .refine((values) => Boolean(values.en?.trim()), "validation.english_required"),
  note: z.string().max(255, "validation.length_max"),
  publish: z.boolean(),
})
export type ImpersonationInput = z.infer<typeof impersonationSchema>
export type TranslationInput = z.infer<typeof translationSchema>
export type LegalVersionInput = z.infer<typeof legalVersionSchema>
