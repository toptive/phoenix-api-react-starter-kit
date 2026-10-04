// Minimal RFC 4180 CSV for i18n/translations.csv (every field quoted, "\n" line ends).
import { readFileSync, writeFileSync } from "node:fs"
import { fileURLToPath } from "node:url"

export const CSV_PATH = fileURLToPath(new URL("../translations.csv", import.meta.url))

export function parse(text) {
  const rows = []
  let row = []
  let field = ""
  let quoted = false
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { field += '"'; i++ }
      else if (c === '"') quoted = false
      else field += c
    } else if (c === '"') quoted = true
    else if (c === ",") { row.push(field); field = "" }
    else if (c === "\n") { row.push(field); rows.push(row); row = []; field = "" }
    else if (c !== "\r") field += c
  }
  if (field !== "" || row.length > 0) { row.push(field); rows.push(row) }
  return rows
}

export function read() {
  const [header, ...rows] = parse(readFileSync(CSV_PATH, "utf8"))
  const locales = header.slice(1)
  const entries = rows.map(([key, ...values]) => ({ key, values: Object.fromEntries(locales.map((l, i) => [l, values[i] ?? ""])) }))
  return { locales, entries }
}

export function write({ locales, entries }) {
  const quote = (v) => `"${String(v).replaceAll('"', '""')}"`
  const sorted = [...entries].sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0))
  const lines = [["key", ...locales], ...sorted.map((e) => [e.key, ...locales.map((l) => e.values[l] ?? "")])]
  writeFileSync(CSV_PATH, lines.map((cols) => cols.map(quote).join(",")).join("\n") + "\n")
}
