// pnpm i18n:build — i18n/translations.csv → i18n/locales/<locale>.json (flat, sorted).
// Empty cells fall back to the first (default) locale, like the backend does.
// The backend compiles the CSV itself; these JSON files serve tests and tooling.
import { mkdirSync, writeFileSync } from "node:fs"
import { fileURLToPath } from "node:url"

import { read } from "./csv.mjs"

const { locales, entries } = read()
const dir = fileURLToPath(new URL("../locales/", import.meta.url))
mkdirSync(dir, { recursive: true })

for (const locale of locales) {
  const catalog = Object.fromEntries(entries.map((e) => [e.key, e.values[locale] || e.values[locales[0]]]))
  writeFileSync(`${dir}${locale}.json`, JSON.stringify(catalog, null, 2) + "\n")
}
console.log(`i18n: ${entries.length} keys → ${locales.map((l) => `locales/${l}.json`).join(", ")}`)
