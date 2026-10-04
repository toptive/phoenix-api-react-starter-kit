// Audit both halves of the shared catalogue: the SPA and the retained backend.
import { readdirSync, readFileSync } from "node:fs"
import path from "node:path"
import ts from "typescript"
import { read, write } from "./csv.mjs"

const root = new URL("../../", import.meta.url).pathname
function files(directory, extensions) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(directory, entry.name)
    if (entry.isDirectory()) return entry.name === "generated" ? [] : files(file, extensions)
    return extensions.some((extension) => file.endsWith(extension)) && !file.includes(".test.") ? [file] : []
  })
}
const catalogue = read()
const keys = new Set(catalogue.entries.map((entry) => entry.key))
const namespaces = new Set([...keys].map((key) => key.split(".")[0]))
const used = new Set()
const failures = []
if (keys.size !== catalogue.entries.length) failures.push("Duplicate CSV keys")
const patterns = []
const escape = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
const reference = (value, file, required = false) => {
  if (keys.has(value)) used.add(value)
  else if (required) failures.push(`${path.relative(root, file)}: missing key ${value}`)
  for (const suffix of ["_one", "_other"]) {
    if (keys.has(value + suffix)) used.add(value + suffix)
  }
  // A partial prefix is used when a context builds a key with a dynamic suffix.
  if (value.endsWith(".")) patterns.push(new RegExp(`^${escape(value)}`))
}
for (const file of files(path.join(root, "frontend/src"), [".ts", ".tsx"])) {
  const source = ts.createSourceFile(file, readFileSync(file, "utf8"), ts.ScriptTarget.Latest, true)
  const visit = (node) => {
    if (ts.isStringLiteralLike(node)) {
      const parent = node.parent
      const translation =
        ts.isCallExpression(parent) &&
        parent.expression.getText(source).match(/(?:^|\.)t$/) &&
        parent.arguments[0] === node
      const attribute = ts.isJsxAttribute(parent) && parent.name.getText(source) === "i18nKey"
      reference(
        node.text,
        file,
        translation ||
          attribute ||
          (node.text.includes(".") && !node.text.endsWith(".") && namespaces.has(node.text.split(".")[0])),
      )
    }
    if (ts.isTemplateExpression(node)) {
      const pattern = `^${escape(node.head.text)}${node.templateSpans.map((span) => `[^.]+${escape(span.literal.text)}`).join("")}$`
      if (node.head.text.includes(".")) patterns.push(new RegExp(pattern))
    }
    ts.forEachChild(node, visit)
  }
  visit(source)
}
for (const file of files(path.join(root, "lib"), [".ex", ".heex"]).concat(files(path.join(root, "config"), [".exs"]))) {
  const source = readFileSync(file, "utf8")
  for (const match of source.matchAll(/"([^"\n]+)"/g)) {
    reference(match[1], file)
    if (match[1].includes("#{")) {
      patterns.push(
        new RegExp(
          `^${match[1]
            .split(/#\{[^}]+\}/)
            .map(escape)
            .join("[^.]+")}$`,
        ),
      )
    }
  }
}
for (const key of keys) if (patterns.some((pattern) => pattern.test(key))) used.add(key)
for (const entry of catalogue.entries) {
  for (const locale of ["en", "es"]) {
    if (!entry.values[locale]?.trim()) failures.push(`${entry.key}: empty ${locale}`)
  }
}
const unused = catalogue.entries.filter((entry) => !used.has(entry.key))
if (process.argv.includes("--prune") && failures.length === 0) {
  write({ ...catalogue, entries: catalogue.entries.filter((entry) => used.has(entry.key)) })
  console.log(`Removed ${unused.length} unused keys`)
} else {
  failures.push(...unused.map((entry) => `Unused key: ${entry.key}`))
}
if (failures.length) {
  console.error(failures.join("\n"))
  process.exitCode = 1
} else console.log(`i18n audit passed: ${used.size} keys, English and Spanish complete`)
