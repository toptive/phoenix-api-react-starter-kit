import { setTimeout as delay } from "node:timers/promises"
import { test, expect, text, routes, uniqueEmail } from "./fixtures"

// Keep this journey after sign-in and sudo journeys: it deliberately exhausts a real IP bucket.
test("a throttled sign-in shows the server error and Retry-After toast", async ({ page, api }) => {
  const email = uniqueEmail()
  await page.goto("/session/new")
  await page.getByRole("tab", { name: text("auth.session.tab_password"), exact: true }).click()
  await page.getByLabel(text("fields.email"), { exact: true }).fill(email)
  await page.getByLabel(text("fields.password"), { exact: true }).fill("wrong-password")
  // Fill the form first so the exhausted window stays active through the browser click.
  let primed = false
  for (let window = 0; window < 2 && !primed; window++) {
    for (let attempt = 0; attempt < 11; attempt++) {
      const response = await api.context.post(routes.apiV1AuthSessions.create().url, {
        data: { email, password: "wrong-password" },
      })
      if (response.status() === 429) {
        const remaining = Number(response.headers()["retry-after"])
        if (remaining > 2) primed = true
        // Near expiry, wait for the server's deadline and exhaust a fresh window.
        else await delay(remaining * 1000 + 100)
        break
      }
      expect(response.status()).toBe(401)
    }
  }
  expect(primed).toBe(true)
  const limited = page.waitForResponse(
    (response) => response.request().method() === "POST" && response.url().endsWith("/api/v1/auth/sessions"),
  )
  await page.getByRole("button", { name: text("auth.session.submit"), exact: true }).click()
  const response = await limited
  expect(response.status()).toBe(429)
  expect((await response.json()).error.code).toBe("rate_limited")
  const seconds = Number(response.headers()["retry-after"])
  expect(seconds).toBeGreaterThan(0)
  await expect(page.getByRole("alert")).toContainText(text("errors.api.rate_limited"))
  await expect(page.locator("[data-sonner-toast]")).toContainText(text("errors.retry_after", { count: seconds }))
  await expect(page.getByRole("button", { name: text("auth.session.submit"), exact: true })).toBeEnabled()
})
