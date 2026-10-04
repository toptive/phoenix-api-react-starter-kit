import { test, expect, text, signedIn, invite, accept, confirm, routes, uniqueEmail } from "./fixtures"
import type { Membership } from "../src/api/generated/serializers"

test("invite a second user, accept, change role, remove, rejoin and leave; last owner cannot leave", async ({
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
    await signedIn(page, user, "/settings/members")
    await invite(page, second.user.email)
    const path = await api.mailLink(second.user.email, "/invitations/")
    await signedIn(guest, second)
    await accept(guest, path)
    await page.reload()
    const row = page.getByRole("listitem").filter({ hasText: second.user.email })
    await expect(row).toBeVisible()
    await row
      .getByLabel(text("settings.members.role_for", { name: second.user.name }), { exact: true })
      .selectOption("admin")
    await row.getByRole("button", { name: text("common.save"), exact: true }).click()
    await expect(row.getByRole("button", { name: text("common.save"), exact: true })).toBeDisabled()
    await expect(row.getByText(text("level.admin_full"), { exact: true }).first()).toBeVisible()
    const members = await api.call<Membership[]>(routes.apiV1SettingsMembers.index(), undefined, user.token)
    expect(members.find((member) => member.user?.email === second.user.email)?.role).toBe("admin")
    await row.getByRole("button", { name: text("settings.members.remove"), exact: true }).click()
    await confirm(page, text("settings.members.remove"))
    await expect(row).toHaveCount(0)
    await guest.goto("/dashboard")
    expect((await api.bootstrap(second.token)).auth!.organization.id).not.toBe(
      (await api.bootstrap(user.token)).auth!.organization.id,
    )
    await invite(page, second.user.email)
    const again = await api.mailLink(second.user.email, "/invitations/", [path])
    await accept(guest, again)
    await guest.goto("/settings/members")
    await guest.getByRole("button", { name: text("settings.members.leave"), exact: true }).click()
    await confirm(guest, text("settings.members.leave"))
    await expect(guest).toHaveURL(/\/dashboard$/)
    await page.reload()
    await expect(row).toHaveCount(0)
    await page.getByRole("button", { name: text("settings.members.leave"), exact: true }).click()
    const refusal = page.waitForResponse(
      (response) => response.request().method() === "DELETE" && response.url().includes("/api/v1/settings/members/"),
    )
    await confirm(page, text("settings.members.leave"))
    expect((await (await refusal).json()).error.code).toBe("last_owner")
    await expect(page.getByRole("alert")).toBeVisible()
    await expect(page).toHaveURL(/\/settings\/members$/)
  } finally {
    await context.close()
  }
})

test("revoke a pending invitation and the recipient can no longer accept it", async ({ page, api, user }) => {
  await signedIn(page, user)
  const email = uniqueEmail()
  await invite(page, email)
  const path = await api.mailLink(email, "/invitations/")
  const row = page.getByRole("listitem").filter({ hasText: email })
  await row.getByRole("button", { name: text("settings.members.revoke"), exact: true }).click()
  await confirm(page, text("settings.members.revoke"))
  await expect(row).toHaveCount(0)
  await page.goto(path)
  await expect(page.getByRole("alert")).toContainText(text("errors.api.invitation_invalid"))
})
