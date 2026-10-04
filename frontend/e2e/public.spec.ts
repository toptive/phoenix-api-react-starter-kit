import { test, expect, text } from "./fixtures"

test("the public landing switches locale and links to sign-up", async ({ page }) => {
  await page.goto("/")
  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute("href", /\/$/)
  await page.getByRole("button", { name: new RegExp(text("locale.label")) }).click()
  await page.getByRole("menuitemradio", { name: text("locale.name.es"), exact: true }).click()
  await expect(page).toHaveURL(/\/es$/)
  await expect(page.getByRole("link", { name: text("nav.sign_in", {}, "es"), exact: true }).first()).toBeVisible()
  await page.reload()
  await expect(page.locator("html")).toHaveAttribute("lang", "es")
  await page
    .getByRole("link", { name: text("nav.sign_up", {}, "es"), exact: true })
    .first()
    .click()
  await expect(page).toHaveURL(/\/registration\/new/)
})
