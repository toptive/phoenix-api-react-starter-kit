import { test, expect, text, routes, signedIn, storedToken, confirm, promoteAdmin } from "./fixtures"

// Opt in only after the backend admin lane lands. Its test AI adapter must replace
// the upstream HTTP boundary for Fill; the browser never intercepts API responses.
test.beforeEach(() => {
  test.skip(
    process.env.E2E_ADMIN !== "1",
    "Phoenix admin area is being built in parallel; enable E2E_ADMIN=1 after it lands with a test AI adapter.",
  )
})

test("texts: search, edit a cell, reload the catalogue, filter and fill missing Spanish", async ({
  page,
  api,
  user,
}) => {
  promoteAdmin(user.user.id)
  await signedIn(page, user, "/admin/translations")
  await page.getByRole("searchbox", { name: text("admin.translations.search"), exact: true }).fill("auth.session.title")
  await page.getByRole("searchbox").press("Enter")
  await expect(page).toHaveURL(/q=auth.session.title/)
  await page
    .getByRole("button", {
      name: text("admin.translations.edit", { key: "auth.session.title", locale: "en" }),
      exact: true,
    })
    .click()
  const original = { en: text("auth.session.title"), es: text("auth.session.title", {}, "es") }
  const edited = "Browser sign-in title"
  await page.getByLabel(text("locale.name.en"), { exact: true }).fill(edited)
  await page.getByLabel(text("locale.name.en"), { exact: true }).press("Enter")
  await expect(page.getByText(edited, { exact: true })).toBeVisible()
  expect((await api.call<Record<string, string>>(routes.apiV1Locale.show("en")))["auth.session.title"]).toBe(edited)
  await api.call(routes.apiV1AdminTranslation.update("auth.session.title"), { locale: "es", value: "" }, user.token)
  await page.getByRole("combobox", { name: text("admin.translations.filter_missing"), exact: true }).selectOption("es")
  await expect(page).toHaveURL(/missing=es/)
  await page
    .getByRole("button", { name: text("admin.translations.fill", { language: text("locale.name.es") }), exact: true })
    .click()
  await expect(page.getByRole("status").filter({ hasText: /\d/ })).toBeVisible()
  await api.call(
    routes.apiV1AdminTranslation.update("auth.session.title"),
    { locale: "en", value: original.en },
    user.token,
  )
  await api.call(
    routes.apiV1AdminTranslation.update("auth.session.title"),
    { locale: "es", value: original.es },
    user.token,
  )
})

test("impersonation keeps the admin bearer aside and Back restores the admin account", async ({
  page,
  api,
  user,
  createUser,
}) => {
  const target = await createUser()
  promoteAdmin(user.user.id)
  await signedIn(page, user, `/admin/users/${target.user.id}`)
  for (const role of ["superadmin", "user"]) {
    await page.getByRole("combobox", { name: text("admin.users.role"), exact: true }).selectOption(role)
    await page.getByRole("button", { name: text("common.save_changes"), exact: true }).click()
    await confirm(page, text("common.save_changes"))
    await expect(page.getByRole("button", { name: text("common.save_changes"), exact: true })).toBeDisabled()
    expect((await api.bootstrap(target.token)).auth!.user.role).toBe(role)
  }
  await page.getByLabel(text("admin.users.reason"), { exact: true }).fill("Browser support investigation")
  await page
    .getByRole("button", { name: text("admin.users.impersonate", { email: target.user.email }), exact: true })
    .click()
  await expect(page).toHaveURL(/\/dashboard$/)
  await expect(page.getByText(text("impersonation.banner", { email: target.user.email }))).toBeVisible()
  expect(await storedToken(page)).not.toBe(user.token)
  expect((await api.bootstrap(await storedToken(page))).auth).toMatchObject({
    superadmin: false,
    impersonator: { id: user.user.id },
  })
  await page.goto("/settings/profile/edit")
  await expect(page.getByText(text("impersonation.banner", { email: target.user.email }))).toBeVisible()
  await page.getByRole("button", { name: text("impersonation.stop"), exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/users/)
  expect(await storedToken(page)).toBe(user.token)
  expect(await page.evaluate(() => localStorage.getItem("starterkit:admin-token"))).toBeNull()
})

test("legal: create a bilingual draft, publish it and read the public version", async ({ page, user }) => {
  promoteAdmin(user.user.id)
  await signedIn(page, user, "/admin/legal-documents/terms")
  await page.getByLabel(text("admin.legal.doc_title"), { exact: true }).fill("Browser terms")
  await page.getByLabel(text("admin.legal.body"), { exact: true }).fill("## Browser agreement\n\nPlain text terms.")
  await page.getByRole("button", { name: text("stepper.next"), exact: true }).click()
  await page.getByLabel(text("admin.legal.doc_title"), { exact: true }).fill("Términos del navegador")
  await page.getByLabel(text("admin.legal.body"), { exact: true }).fill("## Acuerdo\n\nTérminos en texto.")
  await page.getByRole("button", { name: text("stepper.next"), exact: true }).click()
  await page.getByLabel(text("admin.legal.note"), { exact: true }).fill("Browser publication")
  await page.getByRole("button", { name: text("stepper.next"), exact: true }).click()
  await page.getByRole("button", { name: text("admin.legal.save"), exact: true }).click()
  const draft = page
    .getByRole("row")
    .filter({ hasText: text("admin.legal.publish") })
    .first()
  await draft.getByRole("button", { name: text("admin.legal.publish"), exact: true }).click()
  await confirm(page, text("admin.legal.publish"))
  await expect(page.getByText(text("flash.legal.published"), { exact: true })).toBeVisible()
  await page.goto("/legal/terms")
  await expect(page.getByRole("heading", { name: "Browser terms", exact: true })).toBeVisible()
  await expect(page.getByText("Plain text terms.", { exact: true })).toBeVisible()
  await page.goto("/es/legal/terms")
  await expect(page.getByRole("heading", { name: "Términos del navegador", exact: true })).toBeVisible()
})

test("audit log searches a real preferences event and discloses its identifiers", async ({ page, user, api }) => {
  promoteAdmin(user.user.id)
  await signedIn(page, user, "/settings/email-preferences/edit")
  await page.getByRole("switch").click()
  await page.getByRole("button", { name: text("common.save_changes"), exact: true }).click()
  await expect(page.getByRole("button", { name: text("common.save_changes"), exact: true })).toBeDisabled()
  await page.goto("/admin/audit-events")
  await page.getByRole("searchbox", { name: text("admin.audit.search"), exact: true }).fill(user.user.id)
  await page.getByRole("searchbox").press("Enter")
  const row = page.getByRole("row").filter({ hasText: "user.optional_emails_stopped" }).first()
  await expect(row).toContainText(user.user.email)
  await row.locator("summary").click()
  await expect(row.getByText(user.user.id, { exact: true }).first()).toBeVisible()
  expect((await api.bootstrap(user.token)).auth!.superadmin).toBe(true)
})

test("Jobs uses the backend ticket URL in a new tab when the dashboard is enabled", async ({ page, user, api }) => {
  promoteAdmin(user.user.id)
  await signedIn(page, user, "/admin")
  const available = (await api.bootstrap(user.token)).app.jobsDashboard
  const button = page.getByRole("button", { name: text("admin.nav.jobs"), exact: true })
  if (!available) {
    await expect(button).toHaveCount(0)
    return
  }
  const response = page.waitForResponse(
    (response) => response.url().endsWith("/api/v1/admin/jobs-access") && response.request().method() === "POST",
  )
  const popup = page.waitForEvent("popup")
  await button.click()
  const result = await response
  expect(result.status()).toBe(201)
  const dashboard = await popup
  await dashboard.waitForURL(/\/admin\/jobs/)
  expect(await dashboard.evaluate(() => window.opener)).toBeNull()
  await dashboard.close()
})
