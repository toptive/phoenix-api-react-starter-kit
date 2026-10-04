import path from "node:path"

import tailwindcss from "@tailwindcss/vite"
import react from "@vitejs/plugin-react"
import { defineConfig, type Plugin } from "vite"

// The nodejs workers `require()` priv/ssr/ssr.js: mark the folder as CommonJS (the repo
// package.json says "type": "module").
const commonJsMarker: Plugin = {
  name: "ssr-commonjs-marker",
  generateBundle() {
    this.emitFile({ type: "asset", fileName: "package.json", source: '{ "type": "commonjs" }\n' })
  },
}

// Client bundle → priv/static/assets (+ .vite/manifest.json read by StarterKitWeb.Vite).
// SSR bundle (`vite build --ssr`) → priv/ssr/ssr.js, one self-contained CommonJS file
// (noExternal) so the release image needs node but no node_modules.
const port = Number(process.env.VITE_PORT ?? 5173)

export default defineConfig(({ isSsrBuild, mode }) => ({
  root: "assets",
  base: isSsrBuild ? "/" : "/assets/",
  publicDir: false,
  plugins: isSsrBuild ? [react(), tailwindcss(), commonJsMarker] : [react(), tailwindcss()],
  resolve: {
    alias: { "@": path.resolve(import.meta.dirname, "assets/js") },
  },
  server: {
    host: "127.0.0.1",
    port,
    strictPort: true,
    origin: `http://127.0.0.1:${port}`,
    cors: { origin: /^http:\/\/(localhost|127\.0\.0\.1):\d+$/ },
  },
  ssr: { noExternal: true },
  // The SSR bundle ships React's production build only (smaller, less memory per worker).
  define: isSsrBuild && mode === "production" ? { "process.env.NODE_ENV": JSON.stringify("production") } : {},
  build: isSsrBuild
    ? {
        outDir: "../priv/ssr",
        emptyOutDir: true,
        minify: mode === "production",
        rolldownOptions: { output: { format: "cjs", entryFileNames: "ssr.js", inlineDynamicImports: true } },
      }
    : {
        outDir: "../priv/static/assets",
        assetsDir: "",
        emptyOutDir: true,
        manifest: true,
        rolldownOptions: { input: "js/app.tsx" },
      },
}))
