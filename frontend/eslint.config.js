// ESLint catches what TypeScript cannot. Run with --max-warnings 0 (pnpm lint).
import js from "@eslint/js"
import i18next from "eslint-plugin-i18next"
import reactHooks from "eslint-plugin-react-hooks"
import globals from "globals"
import tseslint from "typescript-eslint"

// Tailwind palette colours (text-blue-500, bg-[#fff], …) are forbidden: use theme tokens
// (text-primary, bg-muted, …) so a product re-skins by editing src/styles/theme.css.
const HARD_CODED_COLOR =
  /\b(?:bg|text|border|ring|fill|stroke|from|via|to|outline|decoration|divide|shadow|accent|caret)-(?:slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose|black|white)(?:-\d{2,3})?\b|\[#[0-9a-fA-F]{3,8}\]/

const architecture = {
  rules: {
    "api-hooks-only": {
      meta: { schema: [], messages: { direct: "Use @/api hooks for data; the HTTP core belongs to the API layer." } },
      create(context) {
        const file = context.filename
        if (file.includes("/src/api/") || /\.test\.tsx?$/.test(file)) return {}
        return {
          ImportDeclaration(node) {
            if (
              node.source.value === "@/api/http" &&
              node.specifiers.some(
                (specifier) =>
                  specifier.type === "ImportSpecifier" && ["api", "request"].includes(specifier.imported.name),
              )
            )
              context.report({ node, messageId: "direct" })
          },
        }
      },
    },
    "literal-ui-attributes": {
      meta: { schema: [], messages: { literal: 'UI text must come from t("ns.key").' } },
      create(context) {
        return {
          JSXAttribute(node) {
            if (
              ["title", "placeholder", "alt", "aria-label", "label", "description", "help", "submitLabel"].includes(
                node.name.name,
              ) &&
              node.value?.type === "Literal" &&
              typeof node.value.value === "string"
            )
              context.report({ node, messageId: "literal" })
          },
        }
      },
    },
    "kebab-case": {
      meta: { schema: [], messages: { name: "Files and folders must use kebab-case." } },
      create(context) {
        return {
          Program(node) {
            const relative = context.filename.split("/src/")[1]
            if (
              relative &&
              relative.split("/").some((part) => !/^[a-z0-9]+(?:-[a-z0-9]+)*(?:\.[a-z0-9]+)*$/.test(part))
            )
              context.report({ node, messageId: "name" })
          },
        }
      },
    },
  },
}
export default tseslint.config(
  {
    basePath: import.meta.dirname,
    ignores: ["src/api/generated/**", "dist/**", "node_modules/**"],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    basePath: import.meta.dirname,
    files: ["src/**/*.{ts,tsx}"],
    languageOptions: { globals: { ...globals.browser } },
    plugins: { "react-hooks": reactHooks, architecture },
    rules: {
      ...reactHooks.configs.recommended.rules,
      "architecture/kebab-case": "error",
      "architecture/api-hooks-only": "error",
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/no-unused-vars": ["error", { ignoreRestSiblings: true, argsIgnorePattern: "^_" }],
      "@typescript-eslint/consistent-type-imports": ["error", { fixStyle: "inline-type-imports" }],
      "no-restricted-imports": [
        "error",
        {
          paths: [
            { name: "axios", message: "Use @/api hooks for data." },
            { name: "next-themes", message: "Use @/hooks/use-appearance." },
          ],
        },
      ],
      "no-restricted-syntax": [
        "error",
        {
          selector: `Literal[value=${HARD_CODED_COLOR}]`,
          message: "Hard-coded colour: use a theme token (text-primary, bg-muted, …).",
        },
        {
          selector: `TemplateElement[value.raw=${HARD_CODED_COLOR}]`,
          message: "Hard-coded colour: use a theme token (text-primary, bg-muted, …).",
        },
        {
          selector: "CallExpression[callee.name='fetch'], CallExpression[callee.property.name='fetch']",
          message: "Use @/api hooks; fetch belongs only in src/api/http.ts.",
        },
      ],
    },
  },
  {
    // Every user-facing text goes through i18n (t("…")). Owned shadcn primitives are exempt.
    basePath: import.meta.dirname,
    files: ["src/**/*.tsx"],
    ignores: ["src/components/ui/**", "src/**/*.test.tsx"],
    plugins: { i18next, architecture },
    rules: {
      "architecture/literal-ui-attributes": "error",
      "i18next/no-literal-string": ["error", { mode: "jsx-text-only" }],
    },
  },
  {
    // The HTTP core and direct object-storage uploads are allowed to call fetch.
    basePath: import.meta.dirname,
    files: ["src/api/http.ts", "src/api/uploads.ts"],
    rules: {
      "no-restricted-syntax": [
        "error",
        { selector: `Literal[value=${HARD_CODED_COLOR}]`, message: "Use a theme token." },
        { selector: `TemplateElement[value.raw=${HARD_CODED_COLOR}]`, message: "Use a theme token." },
      ],
    },
  },
  {
    // shadcn primitives are owned but generated: keep their upstream style.
    basePath: import.meta.dirname,
    files: ["src/components/ui/**"],
    rules: { "react-hooks/purity": "off", "react-hooks/set-state-in-effect": "off", "react-hooks/refs": "off" },
  },
  {
    basePath: import.meta.dirname,
    files: ["*.config.{js,ts}", "scripts/**/*.mjs", "e2e/**/*.{ts,mjs}"],
    languageOptions: { globals: { ...globals.node } },
  },
  {
    basePath: new URL("..", import.meta.url).pathname,
    files: ["i18n/scripts/**/*.mjs"],
    languageOptions: { globals: { ...globals.node } },
  },
)
