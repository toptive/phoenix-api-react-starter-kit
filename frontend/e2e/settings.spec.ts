import {
  test,
  expect,
  text,
  signedIn,
  storedToken,
  uniqueEmail,
  routes,
  password,
  confirm,
  invite,
  accept,
} from "./fixtures"
import type { AuthSession } from "../src/api/generated/serializers"

test("save the profile and switch language; Spanish UI survives reload", async ({ page, user, api }) => {
  await signedIn(page, user, "/settings/profile/edit")
  await expect(page.locator('input[type="file"]')).toHaveCount(0)
  await page.getByLabel(text("fields.name"), { exact: true }).fill("Edited Browser User")
  await page.getByLabel(text("fields.language"), { exact: true }).selectOption("es")
  await page.getByRole("button", { name: text("common.save_changes"), exact: true }).click()
  await expect(page.getByRole("heading", { name: text("settings.profile.title", {}, "es"), exact: true })).toBeVisible()
  await expect(page.getByRole("button", { name: text("common.save_changes", {}, "es"), exact: true })).toBeDisabled()
  await page.reload()
  await expect(page.getByLabel(text("fields.name", {}, "es"), { exact: true })).toHaveValue("Edited Browser User")
  expect((await api.bootstrap(user.token)).auth!.user).toMatchObject({ name: "Edited Browser User", locale: "es" })
})

test("turn optional emails off and back on, preserving each choice after reload", async ({ page, user, api }) => {
  await signedIn(page, user, "/settings/email-preferences/edit")
  for (const enabled of [false, true]) {
    const control = page.getByRole("switch")
    if ((await control.getAttribute("aria-checked")) !== String(enabled)) await control.click()
    await page.getByRole("button", { name: text("common.save_changes"), exact: true }).click()
    await expect(page.getByRole("button", { name: text("common.save_changes"), exact: true })).toBeDisabled()
    await page.reload()
    await expect(page.getByRole("switch")).toHaveAttribute("aria-checked", String(enabled))
    expect(await api.call(routes.apiV1SettingsEmailPreferences.show(), undefined, user.token)).toEqual({
      optionalEmails: enabled,
    })
  }
})

test("sign out another device while this device stays signed in", async ({ page, browser, createUser, api }) => {
  const user = await createUser({ withPassword: true })
  const other = await api.call<AuthSession>(routes.apiV1AuthSessions.create(), { email: user.user.email, password })
  const context = await browser.newContext({
    baseURL: process.env.E2E_BASE_URL ?? `http://localhost:${process.env.E2E_VITE_PORT ?? "5174"}`,
  })
  const secondPage = await context.newPage()
  try {
    await signedIn(secondPage, { ...user, ...other, token: other.token! })
    await signedIn(page, user, "/settings/sessions")
    const row = page
      .getByRole("listitem")
      .filter({ hasNot: page.getByText(text("settings.sessions.this_device"), { exact: true }) })
      .filter({ has: page.getByRole("button", { name: text("settings.sessions.sign_out"), exact: true }) })
    await expect(row).toHaveCount(1)
    await row.getByRole("button", { name: text("settings.sessions.sign_out"), exact: true }).click()
    await confirm(page, text("settings.sessions.sign_out"))
    await expect(
      page
        .getByRole("listitem")
        .filter({ has: page.getByRole("button", { name: text("settings.sessions.sign_out"), exact: true }) }),
    ).toHaveCount(1)
    await secondPage.goto("/settings/sessions")
    await expect(secondPage).toHaveURL(/\/session\/new/)
    expect(await storedToken(secondPage)).toBeNull()
    expect((await api.bootstrap(user.token)).auth!.user.id).toBe(user.user.id)
  } finally {
    await context.close()
  }
})

test("email changes only after the mailed confirmation button, and its link is single use", async ({
  page,
  user,
  api,
}) => {
  const email = uniqueEmail()
  await signedIn(page, user, "/settings/email/edit")
  await page.getByLabel(text("fields.new_email"), { exact: true }).fill(email)
  await page.getByRole("button", { name: text("settings.email.submit"), exact: true }).click()
  await expect(page.getByText(text("settings.email.check_email", { email }))).toBeVisible()
  expect((await api.bootstrap(user.token)).auth!.user.email).toBe(user.user.email)
  const path = await api.mailLink(email, "/settings/email-confirmations/")
  await page.goto(path)
  await expect(
    page.getByRole("button", { name: text("settings.email_confirmation.submit"), exact: true }),
  ).toBeVisible()
  expect((await api.bootstrap(user.token)).auth!.user.email).toBe(user.user.email)
  await page.getByRole("button", { name: text("settings.email_confirmation.submit"), exact: true }).click()
  await expect(page).toHaveURL(/\/settings\/profile\/edit$/)
  expect((await api.bootstrap(user.token)).auth!.user.email).toBe(email)
  await page.goto(path)
  await expect(page.getByRole("alert")).toContainText(text("errors.api.email_change_invalid"))
})

test("changing the password replaces this bearer and revokes the other browser session", async ({
  page,
  browser,
  api,
  createUser,
}) => {
  const user = await createUser({ withPassword: true })
  const other = await api.call<AuthSession>(routes.apiV1AuthSessions.create(), { email: user.user.email, password })
  const context = await browser.newContext({
    baseURL: process.env.E2E_BASE_URL ?? `http://localhost:${process.env.E2E_VITE_PORT ?? "5174"}`,
  })
  const otherPage = await context.newPage()
  const replacement = "Replacement-password-2026"
  try {
    await signedIn(otherPage, { ...user, ...other, token: other.token! })
    await signedIn(page, user, "/settings/password/edit")
    await page.getByLabel(text("fields.new_password"), { exact: true }).fill(replacement)
    await page.getByLabel(text("fields.password_confirmation"), { exact: true }).fill("different-password")
    await page.getByRole("button", { name: text("settings.password.submit"), exact: true }).click()
    await expect(page.getByRole("alert")).toContainText(text("validation.password_mismatch"))
    await page.getByLabel(text("fields.password_confirmation"), { exact: true }).fill(replacement)
    await page.getByRole("button", { name: text("settings.password.submit"), exact: true }).click()
    await expect.poll(() => storedToken(page)).not.toBe(user.token)
    await expect(page.getByText(text("settings.password.saved"))).toBeVisible()
    await otherPage.goto("/settings/sessions")
    await expect(otherPage).toHaveURL(/\/session\/new/)
    expect(await storedToken(otherPage)).toBeNull()
    await page.reload()
    await expect(page.getByRole("heading", { name: text("settings.password.title_change"), exact: true })).toBeVisible()
    expect(
      (
        await api.call<AuthSession>(routes.apiV1AuthSessions.create(), {
          email: user.user.email,
          password: replacement,
        })
      ).token,
    ).toBeTruthy()
  } finally {
    await context.close()
  }
})

test("account deletion is blocked by ownership, then allowed after transferring it", async ({
  page,
  browser,
  api,
  user,
  createUser,
}) => {
  const second = await createUser()
  const context = await browser.newContext({
    baseURL: process.env.E2E_BASE_URL ?? `http://localhost:${process.env.E2E_VITE_PORT ?? "5174"}`,
  })
  const guest = await context.newPage()
  try {
    await signedIn(page, user)
    await invite(page, second.user.email)
    await signedIn(guest, second)
    await accept(guest, await api.mailLink(second.user.email, "/invitations/"))
    await page.goto("/settings/account/edit")
    await expect(page.getByText(text("settings.account.blocked_title"))).toBeVisible()
    await expect(page.getByRole("button", { name: text("settings.account.delete"), exact: true })).toHaveCount(0)
    await page.getByRole("button", { name: text("settings.members.nav"), exact: true }).click()
    const row = page.getByRole("listitem").filter({ hasText: second.user.email })
    await row
      .getByLabel(text("settings.members.role_for", { name: second.user.name }), { exact: true })
      .selectOption("owner")
    await row.getByRole("button", { name: text("common.save"), exact: true }).click()
    await expect(row.getByRole("button", { name: text("common.save"), exact: true })).toBeDisabled()
    await page.goto("/settings/account/edit")
    await page.getByRole("button", { name: text("settings.account.delete"), exact: true }).click()
    await expect(page.getByRole("alertdialog")).toContainText(text("settings.account.confirm_consequence"))
    await confirm(page, text("settings.account.delete"))
    await expect(page).toHaveURL(/\/$/)
    expect(await storedToken(page)).toBeNull()
    await page.goto("/dashboard")
    await expect(page).toHaveURL(/\/session\/new/)
    expect((await api.bootstrap(second.token)).auth!.membership.role).toBe("owner")
  } finally {
    await context.close()
  }
})

test("appearance chooses dark, light and system and persists per browser", async ({ page, user }) => {
  await signedIn(page, user, "/settings/appearance/edit")
  await page.getByRole("radio", { name: text("appearance.dark"), exact: true }).click()
  await expect(page.locator("html")).toHaveClass(/dark/)
  await page.reload()
  await expect(page.locator("html")).toHaveClass(/dark/)
  await page.getByRole("radio", { name: text("appearance.light"), exact: true }).click()
  await expect(page.locator("html")).not.toHaveClass(/dark/)
  await page.getByRole("radio", { name: text("appearance.system"), exact: true }).click()
  await page.emulateMedia({ colorScheme: "dark" })
  await expect(page.locator("html")).toHaveClass(/dark/)
})
