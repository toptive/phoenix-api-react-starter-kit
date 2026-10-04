// OPENROUTER_API_KEY=… pnpm i18n:translate [--all] [locale…]
// Fills empty cells from the default locale through OpenRouter (never OpenAI or
// Anthropic directly). --all retranslates every cell. Model: OPENROUTER_MODEL.
import { read, write } from "./csv.mjs"

const key = process.env.OPENROUTER_API_KEY
if (!key) {
  console.error("Set OPENROUTER_API_KEY")
  process.exit(1)
}
const model = process.env.OPENROUTER_MODEL || "openai/gpt-4o-mini"
const args = process.argv.slice(2)
const all = args.includes("--all")
const csv = read()
const source = csv.locales[0]
const targets = args.filter((a) => !a.startsWith("--")).length ? args.filter((a) => !a.startsWith("--")) : csv.locales.slice(1)

async function translate(batch, to) {
  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
    body: JSON.stringify({
      model,
      temperature: 0.2,
      response_format: { type: "json_object" },
      messages: [
        {
          role: "system",
          content: `You translate short user-interface strings for a web app used by non-technical people. Translate from ${source} to ${to}. Keep the same JSON keys. Keep {{placeholders}} and <tags> exactly. Use plain, friendly words. Answer with a JSON object only.`,
        },
        { role: "user", content: JSON.stringify(batch) },
      ],
    }),
  })
  if (!response.ok) throw new Error(`OpenRouter ${response.status}: ${await response.text()}`)
  const body = await response.json()
  return JSON.parse(body.choices[0].message.content)
}

for (const to of targets) {
  const pending = csv.entries.filter((e) => e.values[source] && (all || !e.values[to]))
  for (let i = 0; i < pending.length; i += 40) {
    const slice = pending.slice(i, i + 40)
    const result = await translate(Object.fromEntries(slice.map((e) => [e.key, e.values[source]])), to)
    for (const entry of slice) if (typeof result[entry.key] === "string") entry.values[to] = result[entry.key]
    console.log(`i18n: ${to} ${Math.min(i + 40, pending.length)}/${pending.length}`)
  }
}
write(csv)
