import { useParams } from "@tanstack/react-router"
import { useTranslation } from "react-i18next"
import { useLegalPage } from "@/api/hooks/public"
import { useAppConfig } from "@/api/hooks/bootstrap"
import { LegalBody } from "@/components/app/legal-body"
import { formatDate } from "@/lib/format"
import { paths } from "@/lib/paths"
import { Seo, jsonLdText } from "@/components/app/seo"
import ErrorShow from "@/pages/errors/show"
import { ApiError } from "@/api/http"
export default function LegalPage() {
  const { slug = "" } = useParams({ strict: false }) as { slug?: string }
  const { t, i18n } = useTranslation()
  const { app, locales } = useAppConfig()
  const legal = useLegalPage(slug, i18n.language)
  if (legal.error) return <ErrorShow status={legal.error instanceof ApiError ? legal.error.status : 500} />
  if (!legal.data) return <p role="status">{t("common.loading")}</p>
  return (
    <article className="mx-auto max-w-2xl px-4 py-16 sm:px-6">
      <Seo title={legal.data.title} path={`/legal/${slug}`} publicUrl={app.publicUrl} locales={locales} />
      <h1 className="text-3xl font-bold sm:text-4xl">{legal.data.title}</h1>
      <p className="mt-3 text-sm text-muted-foreground">
        {t("legal.version", { version: legal.data.version, date: formatDate(legal.data.publishedAt, i18n.language) })}
      </p>
      <div className="mt-10">
        <LegalBody body={legal.data.body} />
      </div>
      <script type="application/ld+json">
        {jsonLdText({
          "@context": "https://schema.org",
          "@type": "BreadcrumbList",
          itemListElement: [
            { "@type": "ListItem", position: 1, name: t("app.name"), item: app.publicUrl + paths.home(i18n.language) },
            {
              "@type": "ListItem",
              position: 2,
              name: legal.data.title,
              item: app.publicUrl + paths.legal(slug, i18n.language),
            },
          ],
        })}
      </script>
    </article>
  )
}
