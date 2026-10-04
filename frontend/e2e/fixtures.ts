import { randomUUID } from "node:crypto"
import { execFileSync } from "node:child_process"
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
export type TestUser = AuthSession & { token: string; magicPath: string; workspace: string }

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
          for (const mail of mailbox.data) {
            if (!mail.to.some((recipient) => recipient.includes(email))) continue
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
    await this.call(routes.apiV1AuthRegistration.create(), {
      name: "Browser Tester",
      email,
      termsAccepted: true,
      locale: "en",
    })
    const magicPath = await this.mailLink(email, "/magic-links/")
    const token = magicPath.split("/").at(-1)!
    let session = await this.call<AuthSession>(routes.apiV1AuthMagicLinkSession.create(token), {})
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
    return { ...session, token: session.token!, magicPath, workspace }
  }
  bootstrap(token: string) {
    return this.call<Bootstrap>(routes.apiV1Bootstrap.show(), undefined, token)
  }
}

type Fixtures = { catalogues: void; api: TestApi; createUser: TestApi["createUser"]; user: TestUser }
export const test = base.extend<Fixtures>({
  catalogues: [
    async ({ api }, use) => {
      Object.assign(en, await api.call(routes.apiV1Locale.show("en")))
      Object.assign(es, await api.call(routes.apiV1Locale.show("es")))
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

/** Only moves time for a session created by this test; account setup stays through HTTP. */
export function expireSudo(sessionId: string) {
  if (!/^[0-9a-f-]{36}$/.test(sessionId)) throw new Error("Invalid session id")
  const database = process.env.E2E_PGDATABASE ?? "starter_kit_e2e"
  if (!/(?:e2e|test)/.test(database)) throw new Error("Sudo clock fixture requires an isolated e2e/test database")
  execFileSync(
    "psql",
    [
      "-X",
      "-v",
      "ON_ERROR_STOP=1",
      "-c",
      `UPDATE sessions SET sudo_until = NOW() - INTERVAL '1 minute' WHERE id = '${sessionId}'`,
    ],
    {
      env: {
        ...process.env,
        PGDATABASE: database,
        PGUSER: process.env.PGUSER ?? "postgres",
        PGPASSWORD: process.env.PGPASSWORD ?? "postgres",
      },
      stdio: "pipe",
    },
  )
}

export function promoteAdmin(userId: string) {
  if (!/^[0-9a-f-]{36}$/.test(userId)) throw new Error("Invalid user id")
  const database = process.env.E2E_PGDATABASE ?? "starter_kit_e2e"
  if (!/(?:e2e|test)/.test(database)) throw new Error("Admin fixture requires an isolated e2e/test database")
  execFileSync(
    "psql",
    ["-X", "-v", "ON_ERROR_STOP=1", "-c", `UPDATE users SET role = 'superadmin' WHERE id = '${userId}'`],
    {
      env: {
        ...process.env,
        PGDATABASE: database,
        PGUSER: process.env.PGUSER ?? "postgres",
        PGPASSWORD: process.env.PGPASSWORD ?? "postgres",
      },
      stdio: "pipe",
    },
  )
}

/** Queue a real optional notification; the running API's worker delivers to its mailbox. */
export function sendOptionalEmail(userId: string) {
  if (!/^[0-9a-f-]{36}$/.test(userId)) throw new Error("Invalid user id")
  const database = process.env.E2E_PGDATABASE ?? "starter_kit_e2e"
  if (!/(?:e2e|test)/.test(database)) throw new Error("Mail fixture requires an isolated e2e/test database")
  const apiDirectory =
    process.env.E2E_API_DIR ?? new URL("../../../../phoenix-api-react-starter-kit", import.meta.url).pathname
  execFileSync(
    "mix",
    [
      "run",
      "--no-start",
      "-e",
      `
    Application.ensure_all_started(:ecto_sql)
    Application.ensure_all_started(:postgrex)
    Application.ensure_all_started(:oban)
    Application.ensure_all_started(:plug_crypto)
    {:ok, _} = StarterKit.Repo.start_link()
    {:ok, _} = Oban.start_link(repo: StarterKit.Repo, queues: false, plugins: false)
    user = StarterKit.Accounts.get_user!("${userId}")
    {:ok, _} = StarterKit.Notifications.notify(user, :product_update, %{title: "Browser news", summary: "Test newsletter", url: "http://localhost:5173/"})
  `,
    ],
    {
      cwd: apiDirectory,
      env: {
        ...process.env,
        MIX_ENV: "dev",
        PGDATABASE: database,
        SPA_ORIGIN: process.env.E2E_BASE_URL ?? "http://localhost:5173",
      },
      stdio: "pipe",
      timeout: 30_000,
    },
  )
}
