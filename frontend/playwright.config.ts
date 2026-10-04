import { defineConfig, devices } from "@playwright/test"

const baseURL = process.env.E2E_BASE_URL ?? `http://localhost:${process.env.E2E_VITE_PORT ?? "5173"}`
const baseOffURL = process.env.E2E_BASE_OFF_URL ?? "http://localhost:5174"
process.env.E2E_BASE_URL = baseURL
process.env.E2E_BASE_OFF_URL = baseOffURL

function viteCommand(baseURL: string) {
  const url = new URL(baseURL)
  const port = url.port || (url.protocol === "https:" ? "443" : "80")
  return `pnpm dev --host ${url.hostname} --port ${port} --strictPort`
}
export default defineConfig({
  globalSetup: "./e2e/global-setup.ts",
  testDir: "./e2e",
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 180_000,
  expect: { timeout: 10_000 },
  forbidOnly: !!process.env.CI,
  reporter: [["list"], ["html", { open: "never", outputFolder: "playwright-report" }]],
  outputDir: "test-results",
  use: { baseURL, actionTimeout: 15_000, trace: "retain-on-failure", screenshot: "only-on-failure" },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: [
    {
      command: viteCommand(baseURL),
      cwd: "..",
      url: baseURL,
      reuseExistingServer: false,
      env: { VITE_API_URL: "", VITE_DEV_API_URL: process.env.E2E_API_URL ?? "http://localhost:4100" },
      timeout: 60_000,
    },
    ...(process.env.E2E_BILLING === "1"
      ? [
          {
            command: viteCommand(baseOffURL),
            cwd: "..",
            url: baseOffURL,
            reuseExistingServer: false,
            env: { VITE_API_URL: "", VITE_DEV_API_URL: process.env.E2E_API_OFF_URL ?? "http://localhost:4101" },
            timeout: 60_000,
          },
        ]
      : []),
  ],
})
