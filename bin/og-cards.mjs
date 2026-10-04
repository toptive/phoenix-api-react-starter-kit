#!/usr/bin/env node
// Renders the default social cards, one per locale: priv/static/images/og-<locale>.png
// (1200x630, < 150 KB). StarterKitWeb.SEO.default_image/1 picks the card of the page locale.
//
//   bin/og-cards.mjs  # uses the root @playwright/test dependency
//
// The card reads the product, not a copy of it: the colours and the font come from
// frontend/src/styles/theme.css, the logo is priv/static/favicon.svg, and the words are `app.name`
// and `og.tagline` in i18n/locales/<locale>.json. Run it again after a rename, a re-skin or
// a copy change. Offline tool: needs Playwright (any install; PLAYWRIGHT_MODULE points at it)
// and ImageMagick (`magick`) to shrink the PNG.
import { execFileSync } from "node:child_process"
import fs from "node:fs"
import { createRequire } from "node:module"
import path from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const { chromium } = createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE ?? "@playwright/test")
const file = (relative) => pathToFileURL(path.join(root, relative)).href
const outDir = path.join(root, "priv/static/images")
const locales = fs
  .readdirSync(path.join(root, "i18n/locales"))
  .filter((name) => name.endsWith(".json"))
  .map((name) => path.basename(name, ".json"))

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c])

const page = (locale, copy) => `<!doctype html><html lang="${esc(locale)}"><head><meta charset="utf-8">
<link rel="stylesheet" href="${file("frontend/src/styles/theme.css")}">
<style>
@font-face{font-family:"Public Sans Variable";font-weight:100 900;
  src:url(${file("node_modules/@fontsource-variable/public-sans/files/public-sans-latin-wght-normal.woff2")}) format("woff2")}
@font-face{font-family:"Public Sans Variable";font-weight:100 900;unicode-range:U+0100-02BA,U+1E00-1EFF;
  src:url(${file("node_modules/@fontsource-variable/public-sans/files/public-sans-latin-ext-wght-normal.woff2")}) format("woff2")}
*{box-sizing:border-box;margin:0}
body{width:1200px;height:630px;overflow:hidden;position:relative;background:var(--background);color:var(--foreground);
  font-family:var(--typeface-body)}
.bar{position:absolute;left:0;top:0;bottom:0;width:24px;background:var(--primary)}
.brand{position:absolute;left:96px;top:80px;display:flex;align-items:center;gap:24px;font-size:44px;font-weight:700;
  font-family:var(--typeface-heading);color:var(--primary)}
.brand img{width:88px;height:88px}
h1{position:absolute;left:96px;right:96px;top:236px;font-family:var(--typeface-heading);font-size:76px;line-height:1.08;
  font-weight:800;letter-spacing:-.02em;text-wrap:balance}
.mark{position:absolute;left:96px;bottom:72px;width:240px;height:16px;border-radius:999px;background:var(--highlight)}
</style></head><body>
<div class="bar"></div>
<div class="brand"><img src="${file("priv/static/favicon.svg")}" alt="">${esc(copy["app.name"])}</div>
<h1>${esc(copy["og.tagline"])}</h1>
<div class="mark"></div>
</body></html>`

const browser = await chromium.launch()
try {
  for (const locale of locales) {
    const copy = JSON.parse(fs.readFileSync(path.join(root, "i18n/locales", `${locale}.json`), "utf8"))
    for (const key of ["app.name", "og.tagline"]) {
      if (!copy[key]) throw new Error(`${locale}: missing ${key} in i18n/locales/${locale}.json`)
    }

    const html = path.join(outDir, `.og-${locale}.html`)
    const raw = path.join(outDir, `.og-${locale}.raw.png`)
    const dest = path.join(outDir, `og-${locale}.png`)
    fs.writeFileSync(html, page(locale, copy))
    try {
      const tab = await browser.newPage({ viewport: { width: 1200, height: 630 } })
      await tab.goto(pathToFileURL(html).href)
      await tab.evaluate(() => document.fonts.ready)
      await tab.screenshot({ path: raw })
      await tab.close()
      execFileSync("magick", [raw, "-colors", "128", "-strip", `PNG8:${dest}`])
    } finally {
      fs.rmSync(html, { force: true })
      fs.rmSync(raw, { force: true })
    }

    const kb = Math.round(fs.statSync(dest).size / 1024)
    if (kb > 150) throw new Error(`og-${locale}.png is ${kb} KB (limit 150)`)
    console.log(`priv/static/images/og-${locale}.png ${kb} KB`)
  }
} finally {
  await browser.close()
}
