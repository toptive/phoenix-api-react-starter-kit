import { useTranslation } from "react-i18next"

export function jsonLdText(block: unknown): string {
  return JSON.stringify(block).replace(/</g, "\\u003c")
}
/** React 19 hoists title, meta and link tags into the document head. */
export function Seo({
  title,
  description,
  path = "/",
  publicUrl = import.meta.env.VITE_PUBLIC_URL ?? "http://localhost:5173",
  locales = ["en", "es"],
}: {
  title: string
  description?: string
  path?: string
  publicUrl?: string
  locales?: string[]
}) {
  const { i18n } = useTranslation()
  const origin = publicUrl.replace(/\/$/, "")
  const canonical = origin + (i18n.language === locales[0] ? "" : `/${i18n.language}`) + path
  return (
    <>
      <title>{title}</title>
      {import.meta.env.VITE_SITE_INDEXING === "0" && <meta name="robots" content="noindex" />}
      {description && <meta name="description" content={description} />}
      <link rel="canonical" href={canonical} />
      {locales.map((locale, index) => (
        <link
          key={locale}
          rel="alternate"
          hrefLang={locale}
          href={`${origin}${index === 0 ? "" : `/${locale}`}${path}`}
        />
      ))}
      <meta property="og:title" content={title} />
      {description && <meta property="og:description" content={description} />}
      <meta property="og:url" content={canonical} />
      <meta property="og:type" content="website" />
      <meta property="og:locale" content={i18n.language} />
      <script type="application/ld+json">
        {jsonLdText({ "@context": "https://schema.org", "@type": "WebSite", name: title, url: canonical })}
      </script>
    </>
  )
}
