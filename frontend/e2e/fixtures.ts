import { randomUUID } from "node:crypto"
import { seedUser } from "./backend"
export { expireSudo, sendOptionalEmail } from "./backend"
import { test as base, expect, type APIRequestContext, type Page } from "@playwright/test"
import * as routes from "../src/api/generated/routes"
import type { RouteDefinition, Method } from "../src/api/generated/routes"
import type { AuthSession, Bootstrap, Envelope } from "../src/api/generated/serializers"
import en from "../../i18n/locales/en.json" with { type: "json" }
import es from "../../i18n/locales/es.json" with { type: "json" }

export { expect, routes }
export const text = (key: keyof typeof en, bindings: Record<string, string | number> = {}, locale = "en") =>
  Object.entries(bindings).reduce(
    (value, [name, replacement]) => value.replaceAll(`{{${name}}}`, String(replacement)),
    (locale === "es" ? es : en)[key],
  )
export const uniqueEmail = () => `e2e-${randomUUID()}@example.com`
export const password = "Browser-test-password-2026"
export type TestUser = AuthSession & { token: string; workspace: string }

export class TestApi {
  constructor(readonly context: APIRequestContext) {}
  async call<T>(route: RouteDefinition<Method>, data?: unknown, token?: string): Promise<T> {
    for (let attempt = 0; attempt < 4; attempt++) {
      const response = await this.context.fetch(route.url, {
        method: route.method.toUpperCase(),
        ...(data === undefined ? {} : { data }),
        headers: { "Accept-Language": "en", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      })
      if (response.status() === 429 && attempt < 3) {
        // Keep production rate limits intact; wait for their real Retry-After window.
        const delay = Math.min(60, Number(response.headers()["retry-after"] ?? 60)) * 1000
        await new Promise((resolve) => setTimeout(resolve, delay))
        continue
      }
      expect(response.ok(), `${route.method} ${route.url}: ${(await response.text()).slice(0, 1000)}`).toBeTruthy()
      if (response.status() === 204) return undefined as T
      return ((await response.json()) as Envelope<T>).data
    }
    throw new Error("Rate limit did not clear")
  }
  async mailLink(email: string, prefix: string, exclude: string[] = []) {
    let path = ""
    await expect
      .poll(
        async () => {
          const response = await this.context.get(process.env.E2E_MAILBOX_PATH ?? "/dev/mailbox/json")
          expect(response.ok(), "The API must expose the local test mailbox").toBeTruthy()
          const mailbox = (await response.json()) as { data: { to: string[]; text_body: string; html_body: string }[] }
          for (const mail of mailbox.data.filter((mail) => mail.to.some((recipient) => recipient.includes(email)))) {
            const links = `${mail.text_body}\n${mail.html_body}`.match(/https?:\/\/[^\s"<>]+/g) ?? []
            for (const link of links) {
              const candidate = new URL(link.replaceAll("&amp;", "&")).pathname
              if (candidate.startsWith(prefix) && !exclude.includes(candidate)) {
                path = candidate
                return true
              }
            }
          }
          return false
        },
        { timeout: 30_000, message: `Waiting for ${prefix} mail to ${email}` },
      )
      .toBe(true)
    return path
  }
  async createUser(options: { withPassword?: boolean; onboard?: boolean } = {}): Promise<TestUser> {
    const email = uniqueEmail()
    const seeded = seedUser(email)
    const auth = (await this.bootstrap(seeded.token)).auth!
    let session: AuthSession = {
      ...seeded,
      user: auth.user,
      impersonator: auth.impersonator,
      newAccount: false,
    }
    expect(session.token).toBeTruthy()
    if (options.withPassword) {
      session = await this.call<AuthSession>(
        routes.apiV1SettingsPassword.update(),
        { password, passwordConfirmation: password },
        session.token!,
      )
    }
    const workspace = `Workspace ${randomUUID().slice(0, 8)}`
    if (options.onboard !== false) await this.call(routes.apiV1Onboarding.update(), { name: workspace }, session.token!)
    return { ...session, token: session.token!, workspace }
  }
  bootstrap(token: string) {
    return this.call<Bootstrap>(routes.apiV1Bootstrap.show(), undefined, token)
  }
}

type Fixtures = { catalogues: void; api: TestApi; createUser: TestApi["createUser"]; user: TestUser; admin: TestUser }
export const test = base.extend<Fixtures>({
  catalogues: [
    async ({ api }, use) => {
      Object.assign(en, await api.call(routes.apiV1Locales.show("en")))
      Object.assign(es, await api.call(routes.apiV1Locales.show("es")))
      await use()
    },
    { auto: true },
  ],
  api: async ({ playwright }, use) => {
    const context = await playwright.request.newContext({ baseURL: process.env.E2E_API_URL ?? "http://localhost:4100" })
    await use(new TestApi(context))
    await context.dispose()
  },
  createUser: async ({ api }, use) => {
    await use(api.createUser.bind(api))
  },
  admin: async ({ api }, use) => {
    const session = seedUser("e2e-superadmin@example.com", true)
    const auth = (await api.bootstrap(session.token)).auth!
    expect(auth.superadmin).toBe(true)
    await use({
      ...session,
      user: auth.user,
      impersonator: null,
      newAccount: false,
      workspace: auth.organization.name,
    })
  },
  user: async ({ createUser }, use) => {
    await use(await createUser())
  },
})

export async function signedIn(page: Page, user: TestUser, path = "/dashboard") {
  await page.addInitScript((token) => {
    if (!sessionStorage.getItem("e2e:session-seeded")) {
      localStorage.setItem("starterkit:token", token)
      sessionStorage.setItem("e2e:session-seeded", "1")
    }
  }, user.token)
  await page.goto(path)
}
export async function storedToken(page: Page) {
  return (await page.evaluate(() => localStorage.getItem("starterkit:token")))!
}
export async function confirm(page: Page, label: string) {
  await page.getByRole("alertdialog").getByRole("button", { name: label, exact: true }).click()
  await expect(page.getByRole("alertdialog")).toBeHidden()
}
export async function invite(page: Page, email: string) {
  await page.goto("/settings/members")
  await page
    .getByRole("button", { name: text("settings.members.invite"), exact: true })
    .first()
    .click()
  const dialog = page.getByRole("dialog")
  await dialog.getByLabel(text("fields.email"), { exact: true }).fill(email)
  await dialog.getByRole("button", { name: text("stepper.next"), exact: true }).click()
  await dialog.getByRole("button", { name: text("stepper.next"), exact: true }).click()
  await dialog.getByRole("button", { name: text("settings.members.send_invite"), exact: true }).click()
  await expect(dialog).toBeHidden()
}
export async function accept(page: Page, path: string) {
  await page.goto(path)
  await page.getByRole("button", { name: text("invitation.accept"), exact: true }).click()
  await expect(page).toHaveURL(/\/dashboard$/)
}
