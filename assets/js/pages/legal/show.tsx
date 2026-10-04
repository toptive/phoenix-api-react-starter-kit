import { useTranslation } from "react-i18next"

import { LegalBody } from "@/components/app/legal-body"
import { Seo } from "@/components/app/seo"
import { formatDate } from "@/lib/format"
import type { LegalShowProps } from "@/generated/pages"


export default function LegalShow({ page, seo, locale }: LegalShowProps) {
  const { t } = useTranslation()

  return (
    <article className="mx-auto max-w-2xl px-4 py-16 sm:px-6">
      <Seo seo={seo} />
      <h1 className="text-3xl font-bold sm:text-4xl">{page.title}</h1>
      <p className="mt-3 text-sm text-muted-foreground">
        {t("legal.version", { version: page.version, date: formatDate(page.publishedAt, locale) })}
      </p>
      <div className="mt-10">
        <LegalBody body={page.body} />
      </div>
    </article>
  )
}
