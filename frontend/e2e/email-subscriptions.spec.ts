import { test, expect, text, sendOptionalEmail, routes } from "./fixtures"

test("a mailed unsubscribe link previews safely, then opts out without signing in", async ({ page, api, user }) => {
  sendOptionalEmail(user.user.id)
  const path = await api.mailLink(user.user.email, "/email-subscriptions/")
  await page.goto(path)
  await expect(page.getByRole("heading", { name: text("email_opt_out.title"), exact: true })).toBeVisible()
  expect(await api.call(routes.apiV1SettingsEmailPreferences.show(), undefined, user.token)).toEqual({
    optionalEmails: true,
  })
  await page.reload()
  expect(await api.call(routes.apiV1SettingsEmailPreferences.show(), undefined, user.token)).toEqual({
    optionalEmails: true,
  })
  await page.getByRole("button", { name: text("email_opt_out.submit"), exact: true }).click()
  await expect(page.getByRole("heading", { name: text("email_opt_out.done_title"), exact: true })).toBeVisible()
  expect(await api.call(routes.apiV1SettingsEmailPreferences.show(), undefined, user.token)).toEqual({
    optionalEmails: false,
  })
  await page.reload()
  await expect(page.getByRole("heading", { name: text("email_opt_out.done_title"), exact: true })).toBeVisible()
  expect(await page.evaluate(() => localStorage.getItem("starterkit:token"))).toBeNull()
  await page.getByRole("link", { name: text("email_opt_out.settings"), exact: true }).click()
  await expect(page).toHaveURL(/\/session\/new\?returnTo=/)
})
