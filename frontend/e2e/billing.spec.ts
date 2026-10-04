import { test, expect, text, signedIn, routes } from "./fixtures"
import type { BillingOverview } from "../src/api/generated/serializers"

// The kit's billing lane must enable the flag and stub Stripe's upstream HTTP,
// including reconciliation after checkout. Never replace the browser's API.
test.beforeEach(() => {
  test.skip(
    process.env.E2E_BILLING !== "1",
    "Phoenix billing API lane is not available yet; enable E2E_BILLING=1 with Stripe test HTTP stubs after it lands.",
  )
})
test("choose an offer, accept its price, return from checkout and wait for the paid plan", async ({
  page,
  api,
  admin: user,
}) => {
  await signedIn(page, user, "/settings/billing")
  await page.getByRole("radio").first().check()
  await page.getByRole("checkbox").check()
  await page.getByRole("button", { name: new RegExp(text("billing.checkout.submit").split(" (")[0]!) }).click()
  await expect(page).toHaveURL(/\/settings\/billing\?checkout=done/)
  await expect(page.getByText(text("billing.return.active"), { exact: true })).toBeVisible({ timeout: 65_000 })
  expect(
    (await api.call<BillingOverview>(routes.apiV1SettingsBilling.show(), undefined, user.token)).subscription?.paid,
  ).toBe(true)
})
test("a subscribed manager opens the payment portal and returns to billing", async ({ page, admin: user, api }) => {
  await signedIn(page, user, "/settings/billing")
  await page.getByRole("radio").first().check()
  await page.getByRole("checkbox").check()
  await page.getByRole("button", { name: new RegExp(text("billing.checkout.submit").split(" (")[0]!) }).click()
  await expect(page.getByText(text("billing.return.active"), { exact: true })).toBeVisible({ timeout: 65_000 })
  expect(
    (await api.call<BillingOverview>(routes.apiV1SettingsBilling.show(), undefined, user.token)).subscription,
  ).toBeTruthy()
  await page.getByRole("button", { name: text("billing.portal.open"), exact: true }).click()
  await expect(page).toHaveURL(/billing-portal/)
  await page.getByRole("link", { name: /Return/ }).click()
  await expect(page).toHaveURL(/\/settings\/billing$/)
})
