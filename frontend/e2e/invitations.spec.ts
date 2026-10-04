import { test, expect, text, routes, password, invite, signedIn } from "./fixtures"

test("signed-out invitation preserves the return path through sign-in and joins the workspace", async ({
  page,
  browser,
  api,
  user,
  createUser,
}) => {
  const second = await createUser({ withPassword: true })
  await signedIn(page, user)
  await invite(page, second.user.email)
  const path = await api.mailLink(second.user.email, "/invitations/")
  const context = await browser.newContext({
    baseURL: process.env.E2E_BASE_URL ?? `http://localhost:${process.env.E2E_VITE_PORT ?? "5174"}`,
  })
  const visitor = await context.newPage()
  try {
    await visitor.goto(path)
    await expect(
      visitor.getByRole("heading", { name: text("invitation.title", { organization: user.workspace }), exact: true }),
    ).toBeVisible()
    await expect(visitor.getByRole("link", { name: text("invitation.create_account"), exact: true })).toHaveAttribute(
      "href",
      /email=/,
    )
    await visitor.getByRole("link", { name: text("invitation.sign_in"), exact: true }).click()
    await expect(visitor).toHaveURL(/returnTo=/)
    await visitor.getByRole("tab", { name: text("auth.session.tab_password"), exact: true }).click()
    await expect(visitor.getByLabel(text("fields.email"), { exact: true })).toHaveValue(second.user.email)
    await visitor.getByLabel(text("fields.password"), { exact: true }).fill(password)
    await visitor.getByRole("button", { name: text("auth.session.submit"), exact: true }).click()
    await expect(visitor).toHaveURL(new RegExp(path + "$"))
    await visitor.getByRole("button", { name: text("invitation.accept"), exact: true }).click()
    await expect(visitor).toHaveURL(/\/dashboard$/)
    expect((await api.bootstrap(second.token)).auth!.user.id).toBe(second.user.id)
    const token = await visitor.evaluate(() => localStorage.getItem("starterkit:token"))
    expect((await api.bootstrap(token!)).auth!.organization.id).toBe(
      (await api.bootstrap(user.token)).auth!.organization.id,
    )
    await page.reload()
    expect(await api.call(routes.apiV1SettingsInvitations.index(), undefined, user.token)).toEqual([])
  } finally {
    await context.close()
  }
})
