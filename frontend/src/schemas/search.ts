import { z } from "zod"
let supportedLocales: string[] = []
export function setSearchLocales(locales: string[]) {
  supportedLocales = locales
}
const supportedLocale = z
  .string()
  .refine((locale) => supportedLocales.includes(locale))
  .optional()
  .catch(undefined)

const boundedNumber = (fallback: number, maximum: number) =>
  z.preprocess((value) => {
    if (value === undefined || value === "" || value === null || typeof value === "boolean") return fallback
    const number = Number(value)
    return Number.isFinite(number) ? Math.min(maximum, Math.max(1, Math.floor(number))) : fallback
  }, z.number())
export const localeSearchSchema = z.object({ locale: supportedLocale })
export const listSearchSchema = localeSearchSchema.extend({
  q: z.string().trim().catch(""),
  page: boundedNumber(1, 1_000_000),
  perPage: boundedNumber(25, 100),
})
export const translationSearchSchema = listSearchSchema.extend({
  missing: supportedLocale,
})
export const billingSearchSchema = localeSearchSchema.extend({
  checkout: z.literal("done").optional().catch(undefined),
})
export type ListSearch = z.infer<typeof listSearchSchema>
export type TranslationSearch = z.infer<typeof translationSearchSchema>
