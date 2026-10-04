import { useParams } from "@tanstack/react-router"
import { useTranslation } from "react-i18next"
import { useLegalPage } from "@/api/hooks/public"
import { useAppConfig } from "@/api/hooks/bootstrap"
import { LegalBody } from "@/components/app/legal-body"
import { Seo } from "@/components/app/seo"
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
    <article className="mx-auto max-w-3xl px-4 py-16">
      <Seo title={legal.data.title} path={`/legal/${slug}`} publicUrl={app.publicUrl} locales={locales} />
      <h1 className="mb-8 text-3xl font-bold">{legal.data.title}</h1>
      <LegalBody body={legal.data.body} />
    </article>
  )
}
