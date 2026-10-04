import { Head } from "@inertiajs/react"

import type { HomeShowProps } from "@/generated/pages"

type SeoProps = HomeShowProps["seo"]

/**
 * JSON-LD as script text. Inertia's <Head> writes children into the HTML unescaped, so a
 * "</script>" inside any value (a page title, an organization name) would close the tag
 * and run what follows. "\u003c" is the same character to a JSON parser.
 */
export function jsonLdText(block: unknown): string {
  return JSON.stringify(block).replace(/</g, "\\u003c")
}

/**
 * Title, description, canonical, hreflang, Open Graph and JSON-LD for public pages.
 * Built on the server (StarterKitWeb.SEO) and rendered here inside Inertia's <Head>,
 * which SSR writes into the HTML.
 */
export function Seo({ seo }: { seo: SeoProps }) {
  return (
    <Head title={seo.title}>
      <meta head-key="description" name="description" content={seo.description} />
      <link head-key="canonical" rel="canonical" href={seo.canonical} />
      {seo.alternates.map((alt) => (
        <link key={alt.hreflang} head-key={`alternate-${alt.hreflang}`} rel="alternate" hrefLang={alt.hreflang} href={alt.href} />
      ))}
      <meta head-key="og:title" property="og:title" content={seo.title} />
      <meta head-key="og:description" property="og:description" content={seo.description} />
      <meta head-key="og:url" property="og:url" content={seo.canonical} />
      <meta head-key="og:image" property="og:image" content={seo.image} />
      <meta head-key="og:type" property="og:type" content={seo.type} />
      <meta head-key="og:site_name" property="og:site_name" content={seo.siteName} />
      <meta head-key="og:locale" property="og:locale" content={seo.locale} />
      <meta head-key="twitter:card" name="twitter:card" content="summary_large_image" />
      {seo.jsonLd.map((block, index) => (
        <script key={index} head-key={`jsonld-${index}`} type="application/ld+json">
          {jsonLdText(block)}
        </script>
      ))}
    </Head>
  )
}
