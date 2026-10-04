import { test, expect, text, signedIn, routes, invite, accept } from "./fixtures"

test("unknown routes and a regular user's admin route show 404 with a way home", async ({ page, user }) => {
  await page.goto("/this-page-does-not-exist")
  await expect(page.getByRole("heading", { name: text("errors.page.404.title"), exact: true })).toBeVisible()
  await signedIn(page, user, "/admin")
  await expect(page.getByRole("heading", { name: text("errors.page.404.title"), exact: true })).toBeVisible()
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", /noindex/)
})

test("a member opening the manager-only onboarding route sees the forbidden page", async ({
  page,
  browser,
  user,
  api,
  createUser,
}) => {
  const second = await createUser()
  await signedIn(page, user)
  await invite(page, second.user.email)
  const context = await browser.newContext({
    baseURL: process.env.E2E_BASE_URL ?? `http://localhost:${process.env.E2E_VITE_PORT ?? "5174"}`,
  })
  const member = await context.newPage()
  try {
    await signedIn(member, second)
    await accept(member, await api.mailLink(second.user.email, "/invitations/"))
    const denied = await api.context.get(routes.apiV1Onboarding.show().url, {
      headers: { Authorization: `Bearer ${second.token}` },
    })
    expect(denied.status()).toBe(403)
    await member.goto("/onboarding/edit")
    await expect(member.getByRole("heading", { name: text("errors.page.403.title"), exact: true })).toBeVisible()
    await expect(member.locator('meta[name="robots"]')).toHaveAttribute("content", /noindex/)
  } finally {
    await context.close()
  }
})
