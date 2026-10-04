import path from "node:path"
import react from "@vitejs/plugin-react"
import tailwindcss from "@tailwindcss/vite"
import { defineConfig } from "vite"

const outDir = process.env.VITE_OUT_DIR ?? "../priv/static"

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: { alias: { "@": path.resolve(import.meta.dirname, "src") } },
  server: { proxy: { "/api": process.env.VITE_DEV_API_URL ?? "http://localhost:4000" } },
  build: { outDir, emptyOutDir: false },
})
