// ESLint catches what TypeScript cannot. Run with --max-warnings 0 (pnpm lint).
import js from "@eslint/js"
import i18next from "eslint-plugin-i18next"
import reactHooks from "eslint-plugin-react-hooks"
import globals from "globals"
import tseslint from "typescript-eslint"

// Tailwind palette colours (text-blue-500, bg-[#fff], …) are forbidden: use theme tokens
// (text-primary, bg-muted, …) so a product re-skins by editing assets/css/theme.css.
const HARD_CODED_COLOR =
  /\b(?:bg|text|border|ring|fill|stroke|from|via|to|outline|decoration|divide|shadow|accent|caret)-(?:slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose|black|white)(?:-\d{2,3})?\b|\[#[0-9a-fA-F]{3,8}\]/

export default tseslint.config(
  { ignores: ["assets/js/generated/**", "priv/**", "node_modules/**", "deps/**", "_build/**"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ["assets/js/**/*.{ts,tsx}"],
    languageOptions: { globals: { ...globals.browser } },
    plugins: { "react-hooks": reactHooks },
    rules: {
      ...reactHooks.configs.recommended.rules,
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/no-unused-vars": ["error", { ignoreRestSiblings: true, argsIgnorePattern: "^_" }],
      "@typescript-eslint/consistent-type-imports": ["error", { fixStyle: "inline-type-imports" }],
      "no-restricted-imports": [
        "error",
        {
          paths: [
            { name: "react-hook-form", message: "Forms use Inertia's useForm." },
            { name: "axios", message: "Data comes through Inertia props and visits." },
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
          selector: "CallExpression[callee.name='fetch']",
          message: "No fetch for data: use Inertia props and visits (direct uploads use @/lib/uploads).",
        },
      ],
    },
  },
  {
    // Every user-facing text goes through i18n (t("…")). Owned shadcn primitives are exempt.
    files: ["assets/js/**/*.tsx"],
    ignores: ["assets/js/components/ui/**", "assets/js/**/*.test.tsx"],
    plugins: { i18next },
    rules: {
      "i18next/no-literal-string": ["error", { mode: "jsx-text-only" }],
    },
  },
  {
    // Direct uploads talk to object storage: the one allowed fetch.
    files: ["assets/js/lib/uploads.ts", "assets/js/**/*.test.ts"],
    rules: { "no-restricted-syntax": "off" },
  },
  {
    // shadcn primitives are owned but generated: keep their upstream style.
    files: ["assets/js/components/ui/**"],
    rules: { "react-hooks/purity": "off", "react-hooks/set-state-in-effect": "off", "react-hooks/refs": "off" },
  },
  {
    files: ["*.config.{js,ts}", "i18n/scripts/**/*.mjs"],
    languageOptions: { globals: { ...globals.node } },
  },
)
