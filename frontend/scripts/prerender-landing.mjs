import { mkdtempSync, readdirSync, readFileSync, writeFileSync, mkdirSync, rmSync, cpSync } from "node:fs"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"
import { pathToFileURL } from "node:url"
import { build } from "vite"

const frontend = resolve(import.meta.dirname, "..")
const output = resolve(frontend, process.env.VITE_OUT_DIR ?? "../priv/static")
const temporary = mkdtempSync(join(tmpdir(), "starterkit-landing-"))
try {
  await build({
    root: frontend,
    configFile: resolve(frontend, "vite.config.ts"),
    logLevel: "warn",
    ssr: { noExternal: true },
    build: {
      ssr: "src/landing-ssr.tsx",
      outDir: temporary,
      emptyOutDir: true,
      rolldownOptions: { output: { entryFileNames: "landing-ssr.mjs" } },
    },
  })
  const { render } = await import(pathToFileURL(join(temporary, "landing-ssr.mjs")).href)
  const template = readFileSync(join(output, "index.html"), "utf8")
  const marker = '<div id="root"><!--landing--></div>'
  if (!template.includes(marker)) throw new Error("The landing placeholder is missing from the Vite output")
  const portable = join(frontend, "dist")
  rmSync(portable, { recursive: true, force: true })
  for (const locale of readdirSync(resolve(frontend, "../i18n/locales"))
    .filter((file) => file.endsWith(".json"))
    .map((file) => file.slice(0, -5))) {
    let html = await render(locale)
    // React 19 hoists metadata to the start of the server output; put it in the document head.
    const head = []
    html = html.replace(
      /<(?:meta|link)\b[^>]*\/?>|<title\b[^>]*>[\s\S]*?<\/title>|<script\b[^>]*type="application\/ld\+json"[^>]*>[\s\S]*?<\/script>/g,
      (tag) => {
        if (tag.startsWith("<script") && !tag.includes('type="application/ld+json"')) return tag
        head.push(tag)
        return ""
      },
    )
    const page = template
      .replace('<html lang="en">', `<html lang="${locale}">`)
      .replace("</head>", `${head.join("\n")}\n</head>`)
      .replace(marker, `<div id="root">${html}</div>`)
    const directory = locale === "en" ? output : join(output, locale)
    mkdirSync(directory, { recursive: true })
    writeFileSync(join(directory, "index.html"), page)
    // Portable landing artifacts for the sibling SPA kits.
    const dist = join(frontend, "dist", ...(locale === "en" ? [] : [locale]))
    mkdirSync(dist, { recursive: true })
    writeFileSync(join(dist, "index.html"), page)
  }
  cpSync(join(output, "assets"), join(portable, "assets"), { recursive: true })
  console.log("Prerendered landing pages for all bundled locales")
} finally {
  rmSync(temporary, { recursive: true, force: true })
}
