import { mkdtempSync, readdirSync, readFileSync, writeFileSync, mkdirSync, rmSync, cpSync } from "node:fs"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"
import { pathToFileURL } from "node:url"
import { build, loadEnv } from "vite"

const frontend = resolve(import.meta.dirname, "..")
const env = { ...loadEnv("production", frontend, "VITE_"), ...process.env }
const output = resolve(frontend, env.VITE_OUT_DIR ?? "../priv/static")
const temporary = mkdtempSync(join(tmpdir(), "starterkit-public-"))
try {
  await build({
    root: frontend,
    configFile: resolve(frontend, "vite.config.ts"),
    logLevel: "warn",
    ssr: { noExternal: true },
    build: {
      ssr: "src/landing-prerender.tsx",
      outDir: temporary,
      emptyOutDir: true,
      rolldownOptions: { output: { entryFileNames: "landing-prerender.mjs" } },
    },
  })
  const { render, legalPageUrl } = await import(pathToFileURL(join(temporary, "landing-prerender.mjs")).href)
  const template = readFileSync(join(output, "index.html"), "utf8")
  const marker = '<div id="root"><!--landing--></div>'
  if (!template.includes(marker)) throw new Error("The public placeholder is missing from the Vite output")
  const portable = join(frontend, "dist")
  if (portable !== output) rmSync(portable, { recursive: true, force: true })
  const locales = readdirSync(resolve(frontend, "../i18n/locales"))
    .filter((file) => file.endsWith(".json"))
    .map((file) => file.slice(0, -5))
  async function writePage(locale, pathname, legalPage) {
    let html = await render(locale, legalPage, pathname)
    const head = []
    html = html.replace(
      /<(?:meta|link)\b[^>]*\/?>|<title\b[^>]*>[\s\S]*?<\/title>|<script\b[^>]*type="application\/ld\+json"[^>]*>[\s\S]*?<\/script>/g,
      (tag) => {
        head.push(tag.replace(/^<([a-z]+)/, '<$1 data-prerendered="true"'))
        return ""
      },
    )
    const seed = legalPage
      ? `<script id="prerendered-legal" type="application/json">${JSON.stringify({ locale, page: legalPage }).replace(/</g, "\\u003c")}</script>`
      : ""
    const page = template
      .replace('<html lang="en">', `<html lang="${locale}">`)
      .replace("</head>", `${head.join("\n")}\n</head>`)
      .replace(marker, `<div id="root">${html}</div>${seed}`)
    const segments = pathname.split("/").filter(Boolean)
    for (const root of new Set([output, portable])) {
      const directory = join(root, ...segments)
      mkdirSync(directory, { recursive: true })
      writeFileSync(join(directory, "index.html"), page)
    }
  }
  for (const locale of locales) {
    await writePage(locale, locale === "en" ? "/" : `/${locale}`)
    if (!env.VITE_PRERENDER_API_URL) continue
    const origin = env.VITE_PRERENDER_API_URL.replace(/\/+$/, "").replace(/\/api\/v1$/, "")
    for (const slug of ["terms", "privacy", "cookies"]) {
      const route = new URL(legalPageUrl(slug, locale), "http://localhost")
      const response = await fetch(`${origin}${route.pathname}${route.search}`, {
        headers: { Accept: "application/json", "Accept-Language": locale },
        signal: AbortSignal.timeout(15_000),
      })
      if (response.status === 404) continue // No published version yet.
      if (!response.ok) throw new Error(`Legal prerender failed (${response.status}) for ${locale}/${slug}`)
      const { data } = await response.json()
      if (data?.slug !== slug || typeof data.title !== "string" || typeof data.body !== "string")
        throw new Error(`Invalid legal response for ${locale}/${slug}`)
      // Both prefixed default-locale URLs and their canonical unprefixed URLs work.
      await writePage(locale, `/${locale}/legal/${slug}`, data)
      if (locale === "en") await writePage(locale, `/legal/${slug}`, data)
    }
  }
  if (portable !== output) cpSync(join(output, "assets"), join(portable, "assets"), { recursive: true })
  console.log(
    env.VITE_PRERENDER_API_URL
      ? "Prerendered landing and published legal pages for all bundled locales"
      : "Prerendered landing pages; legal pages load from the API at runtime",
  )
} finally {
  rmSync(temporary, { recursive: true, force: true })
}
