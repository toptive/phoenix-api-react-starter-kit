import { test, expect, text, routes, signedIn, storedToken, confirm } from "./fixtures"

test("texts: search, edit a cell, reload the catalogue, filter and fill missing Spanish", async ({
  page,
  api,
  admin: user,
  browser,
}) => {
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
  const edited = `Browser sign-in title ${Date.now()}`
  try {
    await page.getByLabel(text("locale.name.en"), { exact: true }).fill(edited)
    await page.getByLabel(text("locale.name.en"), { exact: true }).press("Enter")
    await expect(page.getByText(edited, { exact: true })).toBeVisible()
    expect((await api.call<Record<string, string>>(routes.apiV1Locales.show("en")))["auth.session.title"]).toBe(edited)
    const anonymous = await browser.newContext({
      baseURL: process.env.E2E_BASE_URL ?? `http://localhost:${process.env.E2E_VITE_PORT ?? "5174"}`,
    })
    try {
      const publicPage = await anonymous.newPage()
      await publicPage.goto("/session/new")
      await expect(publicPage.getByRole("heading", { name: edited, exact: true })).toBeVisible()
    } finally {
      await anonymous.close()
    }
    await api.call(routes.apiV1AdminTranslations.update("auth.session.title"), { locale: "es", value: "" }, user.token)
    await page
      .getByRole("combobox", { name: text("admin.translations.filter_missing"), exact: true })
      .selectOption("es")
    await expect(page).toHaveURL(/missing=es/)
    const fillResponse = page.waitForResponse(
      (response) =>
        response.url().endsWith("/api/v1/admin/translation-fills") && response.request().method() === "POST",
    )
    await page
      .getByRole("button", { name: text("admin.translations.fill", { language: text("locale.name.es") }), exact: true })
      .click()
    const filled = await fillResponse
    if (process.env.E2E_AI === "1") {
      expect(filled.status()).toBe(201)
      await expect(page.getByRole("status").filter({ hasText: /\d/ })).toBeVisible()
    } else {
      expect(filled.status()).toBe(503)
      expect((await filled.json()).error.code).toBe("ai_not_configured")
      await expect(page.getByRole("alert")).toContainText(text("errors.api.ai_not_configured"))
    }
  } finally {
    await api.call(
      routes.apiV1AdminTranslations.update("auth.session.title"),
      { locale: "en", value: original.en },
      user.token,
    )
    await api.call(
      routes.apiV1AdminTranslations.update("auth.session.title"),
      { locale: "es", value: original.es },
      user.token,
    )
  }
})

test("impersonation keeps the admin bearer aside and Back restores the admin account", async ({
  page,
  api,
  admin: user,
  createUser,
}) => {
  const target = await createUser()
  await signedIn(page, user, "/admin/users")
  await page.getByRole("searchbox").fill(target.user.email)
  await page.getByRole("searchbox").press("Enter")
  await expect(page.getByRole("row").filter({ hasText: target.user.email })).toHaveCount(1)
  await page.getByRole("link", { name: target.user.email, exact: true }).click()
  await expect(page).toHaveURL(new RegExp(`/admin/users/${target.user.id}$`))
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
  expect((await api.bootstrap(await storedToken(page))).auth).toMatchObject({
    superadmin: true,
    impersonator: null,
    user: { id: user.user.id },
  })
  expect(await page.evaluate(() => localStorage.getItem("starterkit:admin-token"))).toBeNull()
})

test("legal: create a bilingual draft, publish it and read the public version", async ({ page, admin: user }) => {
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
  await expect(page.getByText("Términos en texto.", { exact: true })).toBeVisible()
})

test("audit log searches a real preferences event and discloses its identifiers", async ({
  page,
  user,
  admin,
  api,
}) => {
  await signedIn(page, user, "/settings/email-preferences/edit")
  await page.getByRole("switch").click()
  await page.getByRole("button", { name: text("common.save_changes"), exact: true }).click()
  await expect(page.getByRole("button", { name: text("common.save_changes"), exact: true })).toBeDisabled()
  await page.evaluate((token) => localStorage.setItem("starterkit:token", token), admin.token)
  await page.goto("/admin/audit-events")
  await page
    .getByRole("searchbox", { name: text("admin.audit.search"), exact: true })
    .fill("user.optional_emails_stopped")
  await page.getByRole("searchbox").press("Enter")
  await expect(page.getByRole("row").filter({ hasText: "user.optional_emails_stopped" }).first()).toBeVisible()
  await page.getByRole("searchbox", { name: text("admin.audit.search"), exact: true }).fill(user.user.id)
  await page.getByRole("searchbox").press("Enter")
  const row = page.getByRole("row").filter({ hasText: "user.optional_emails_stopped" }).first()
  await expect(row).toContainText(user.user.email)
  await row.locator("summary").click()
  await expect(row.getByText(user.user.id, { exact: true }).first()).toBeVisible()
  expect((await api.bootstrap(admin.token)).auth!.superadmin).toBe(true)
})

test("Jobs uses the backend ticket URL in a new tab when the dashboard is enabled", async ({
  page,
  admin: user,
  api,
}) => {
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
  const navigations: string[] = []
  page.context().on("request", (request) => {
    if (request.isNavigationRequest()) navigations.push(request.url())
  })
  const popup = page.context().waitForEvent("page")
  await button.click()
  const result = await response
  expect(result.status()).toBe(201)
  const dashboard = await popup
  const {
    data: { url },
  } = await result.json()
  expect(new URL(url).pathname).toBe("/admin/jobs/session")
  expect(new URL(url).searchParams.get("ticket")).toBeTruthy()
  // The backend consumes the ticket and redirects; observe navigation without driving the dashboard.
  await dashboard.waitForURL(`${new URL(url).origin}/admin/jobs`)
  expect(navigations).toContain(url)
  expect(await dashboard.evaluate(() => window.opener)).toBeNull()
  await dashboard.close()
})

test("organizations: search the workspace and show its real members", async ({ page, api, admin, user }) => {
  const organization = (await api.bootstrap(user.token)).auth!.organization
  await signedIn(page, admin, "/admin/organizations")
  await page.getByRole("searchbox").fill(user.workspace)
  await page.getByRole("searchbox").press("Enter")
  await page.getByRole("link", { name: user.workspace, exact: true }).click()
  await expect(page).toHaveURL(new RegExp(`/admin/organizations/${organization.id}$`))
  await expect(page.getByRole("heading", { name: user.workspace, exact: true })).toBeVisible()
  await expect(page.getByRole("row").filter({ hasText: user.user.email })).toContainText(text("level.owner_full"))
  await page.getByRole("link", { name: user.user.email, exact: true }).click()
  await expect(page).toHaveURL(new RegExp(`/admin/users/${user.user.id}$`))
})
