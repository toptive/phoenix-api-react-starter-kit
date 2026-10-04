import { test, expect, text, signedIn, password, uniqueEmail, expireSudo, storedToken } from "./fixtures"

for (const method of ["password", "magic link"] as const) {
  test(`expired sudo confirms with ${method} and retries the original email change`, async ({
    page,
    api,
    createUser,
  }) => {
    const user = await createUser({ withPassword: method === "password" })
    await signedIn(page, user, "/settings/email/edit")
    const auth = (await api.bootstrap(await storedToken(page))).auth!
    // Expire after the form opened, exercising the API's real 403 and in-place retry.
    expireSudo(auth.sessionId)
    const email = uniqueEmail()
    let attempts = 0
    page.on("request", (request) => {
      if (request.method() === "PUT" && request.url().endsWith("/api/v1/settings/email")) attempts++
    })
    await page.getByLabel(text("fields.new_email"), { exact: true }).fill(email)
    await page.getByRole("button", { name: text("settings.email.submit"), exact: true }).click()
    const dialog = page.getByRole("dialog")
    await expect(dialog.getByRole("heading", { name: text("auth.sudo.title") })).toBeVisible()
    if (method === "password") {
      await dialog.getByLabel(text("fields.password"), { exact: true }).fill("wrong-password")
      await dialog
        .getByRole("button", { name: text("auth.sudo.confirm"), exact: true })
        .first()
        .click()
      await expect(dialog.getByRole("alert")).toContainText(text("errors.api.invalid_credentials"))
      await dialog.getByLabel(text("fields.password"), { exact: true }).fill(password)
      await dialog
        .getByRole("button", { name: text("auth.sudo.confirm"), exact: true })
        .first()
        .click()
    } else {
      await dialog.getByRole("button", { name: text("auth.session.send_link"), exact: true }).click()
      const path = await api.mailLink(user.user.email, "/magic-links/")
      await dialog.getByLabel(text("auth.sudo.link_label"), { exact: true }).fill(`http://localhost:5173${path}`)
      await dialog.getByRole("button", { name: text("auth.sudo.confirm"), exact: true }).click()
    }
    await expect(dialog).toBeHidden()
    await expect(page.getByText(text("settings.email.check_email", { email }))).toBeVisible()
    expect(attempts).toBe(2)
    expect(await storedToken(page)).toBe(user.token)
    expect(await api.mailLink(email, "/settings/email-confirmations/")).toBeTruthy()
    expect(Date.parse((await api.bootstrap(user.token)).auth!.sudoUntil!)).toBeGreaterThan(Date.now())
  })
}
