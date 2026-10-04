// pnpm i18n:merge new-keys.json — adds {"ns.key": "English text"} entries that are not in
// the CSV yet (other locales stay empty for i18n:translate). Existing keys are untouched.
import { readFileSync } from "node:fs"

import { read, write } from "./csv.mjs"

const csv = read()
const known = new Set(csv.entries.map((e) => e.key))
let added = 0
for (const file of process.argv.slice(2)) {
  for (const [key, text] of Object.entries(JSON.parse(readFileSync(file, "utf8")))) {
    if (known.has(key)) continue
    csv.entries.push({ key, values: { [csv.locales[0]]: text } })
    known.add(key)
    added++
  }
}
write(csv)
console.log(`i18n: added ${added} keys`)
