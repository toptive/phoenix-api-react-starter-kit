import { test, expect, text, signedIn, routes } from "./fixtures"
import type { BillingOverview, Membership } from "../src/api/generated/serializers"
import { stripeStubConfig } from "./stripe-stub.mjs"

const billingEnabled = process.env.E2E_BILLING === "1"
const checkoutButton = (price: string) => text("billing.checkout.submit", { price })

test("billing off hides navigation and a direct visit shows the 404 page", async ({ page, api, user }) => {
  const apiURL = billingEnabled
    ? (process.env.E2E_API_OFF_URL ?? "http://localhost:4101")
    : (process.env.E2E_API_URL ?? "http://localhost:4100")
  const spaURL = billingEnabled
    ? (process.env.E2E_BASE_OFF_URL ?? `http://localhost:${Number(process.env.E2E_VITE_PORT ?? "5174") + 1}`)
    : (process.env.E2E_BASE_URL ?? `http://localhost:${process.env.E2E_VITE_PORT ?? "5174"}`)
  const headers = { Authorization: `Bearer ${user.token}` }
  const bootstrap = await api.context.get(new URL(routes.apiV1Bootstrap.show().url, apiURL).href, { headers })
  expect((await bootstrap.json()).data.flags.billing).toBe(false)
  await signedIn(page, user, new URL("/settings/profile/edit", spaURL).href)
  await expect(page.getByRole("heading", { name: text("settings.profile.title"), exact: true })).toBeVisible()
  await expect(page.getByRole("link", { name: text("settings.billing.nav"), exact: true })).toHaveCount(0)
  const refused = page.waitForResponse((response) => response.url().endsWith("/api/v1/settings/billing"))
  await page.goto(new URL("/settings/billing", spaURL).href)
  expect((await refused).status()).toBe(404)
  await expect(page.getByRole("heading", { name: text("errors.page.404.title"), exact: true })).toBeVisible()
})

test.describe("billing enabled", () => {
  test.skip(!billingEnabled, "Requires E2E_BILLING=1 and the local Stripe stub; run bin/e2e to enable billing journeys.")
  test("test offers require acceptance; checkout polls until signed webhooks activate the plan, then opens the portal", async ({
    page,
    api,
    admin,
    createUser,
  }) => {
    const user = await createUser()
    // Test-mode checkout allows operators only, so promote this organization manager to superadmin.
    await api.call(routes.apiV1AdminUsers.update(user.user.id), { role: "superadmin" }, admin.token)
    const organizationId = (await api.bootstrap(user.token)).auth!.organization.id
    const overview = await api.call<BillingOverview>(routes.apiV1SettingsBilling.show(), undefined, user.token)
    expect(overview.sales).toBe("test")
    expect(overview.canManage).toBe(true)
    expect(overview.subscription).toBeNull()
    expect(overview.offers).toEqual(
      stripeStubConfig.offers.map(({ id, amountCents, currency, interval }) => ({
        id,
        amountCents,
        currency,
        interval,
        plan: "pro",
      })),
    )
    await signedIn(page, user, "/settings/billing")
    await expect(page.getByRole("link", { name: text("settings.billing.nav"), exact: true })).toBeVisible()
    await expect(page.getByText(text("billing.test_mode.title"), { exact: true })).toBeVisible()
    await expect(page.getByText(text("billing.plan.free"), { exact: true })).toBeVisible()
    await expect(page.getByRole("radio")).toHaveCount(overview.offers.length)
    const offer = overview.offers[0]!
    const price = new Intl.NumberFormat("en", { style: "currency", currency: offer.currency.toUpperCase() }).format(
      offer.amountCents / 100,
    )
    const pay = page.getByRole("button", { name: checkoutButton(price), exact: true })
    const checkoutRequests: string[] = []
    page.on("request", (request) => {
      if (request.method() === "POST" && request.url().endsWith("/api/v1/settings/billing/checkout-session"))
        checkoutRequests.push(request.url())
    })
    await pay.click()
    await expect(page.getByText(text("billing.checkout.not_accepted"), { exact: true })).toBeVisible()
    expect(checkoutRequests).toHaveLength(0)
    await page.getByRole("checkbox").check()
    // Choosing a different price clears its acceptance before it can be charged.
    await page.getByRole("radio").nth(1).check()
    await expect(page.getByRole("checkbox")).not.toBeChecked()
    await page.getByRole("radio").first().check()
    await page.getByRole("checkbox").check()
    const checkoutResponse = page.waitForResponse(
      (response) =>
        response.request().method() === "POST" && response.url().endsWith("/api/v1/settings/billing/checkout-session"),
    )
    const firstReturnLoad = page.waitForResponse(
      (response) =>
        response.request().method() === "GET" &&
        response.url().endsWith("/api/v1/settings/billing") &&
        new URL(page.url()).searchParams.get("checkout") === "done" &&
        response.ok(),
    )
    await pay.click()
    const checkedOut = await checkoutResponse
    expect(checkedOut.status(), await checkedOut.text()).toBe(201)
    const checkoutURL = new URL((await checkedOut.json()).data.url)
    expect(checkoutURL.origin).toBe(new URL(stripeStubConfig.url).origin)
    expect(checkoutURL.pathname).toMatch(/^\/checkout\/cs_test_[0-9a-f-]+$/)
    await expect(page).toHaveURL(/checkout=done/)
    await firstReturnLoad
    await expect(page.getByText(text("billing.return.confirming"), { exact: true }).first()).toBeVisible()
    await expect(page.getByRole("button", { name: text("billing.return.check_again"), exact: true })).toBeVisible()
    // Observe an unpaid refetch after the initial return request, then send real signed webhooks.
    const pollRequest = await page.waitForRequest(
      (request) => request.method() === "GET" && request.url().endsWith("/api/v1/settings/billing"),
      { timeout: 10_000 },
    )
    const unpaidPoll = await pollRequest.response()
    expect(unpaidPoll?.ok()).toBe(true)
    expect((await unpaidPoll!.json()).data.subscription?.paid).not.toBe(true)
    const delivered = await api.context.post(new URL("/__stub/webhook", stripeStubConfig.url).href, {
      data: { organizationId },
    })
    expect(delivered.status(), await delivered.text()).toBe(200)
    expect((await delivered.json()).results).toEqual([
      { type: "checkout.session.completed", status: 200 },
      { type: "customer.subscription.created", status: 200 },
    ])
    await expect(page.getByText(text("billing.return.active"), { exact: true })).toBeVisible({ timeout: 65_000 })
    await expect(page.getByText(text("billing.plan.pro"), { exact: true })).toBeVisible()
    await expect(page.getByRole("radio")).toHaveCount(0)
    const paid = await api.call<BillingOverview>(routes.apiV1SettingsBilling.show(), undefined, user.token)
    expect(paid.plan).toBe("pro")
    expect(paid.subscription?.paid).toBe(true)
    const portalResponse = page.waitForResponse(
      (response) =>
        response.request().method() === "POST" && response.url().endsWith("/api/v1/settings/billing/portal-session"),
    )
    await page.getByRole("button", { name: text("billing.portal.open"), exact: true }).click()
    const portal = await portalResponse
    expect(portal.status(), await portal.text()).toBe(201)
    const portalURL = new URL((await portal.json()).data.url)
    expect(portalURL.origin).toBe(new URL(stripeStubConfig.url).origin)
    expect(portalURL.pathname).toMatch(/^\/portal\/bps_[0-9a-f-]+$/)
    await expect(page).toHaveURL(/\/settings\/billing$/)
    await expect(page.getByText(text("billing.plan.pro"), { exact: true })).toBeVisible()
    await expect(page.getByText(text("billing.return.active"), { exact: true })).toHaveCount(0)
    await expect(page.getByRole("button", { name: text("billing.return.check_again"), exact: true })).toHaveCount(0)
    const calls = await api.context.get(new URL("/__stub/calls", stripeStubConfig.url).href)
    const recorded = (await calls.json()).calls as { method: string; path: string; form: Record<string, string> }[]
    const checkout = recorded.find((call) => call.path === "/v1/checkout/sessions")!
    expect(checkout.form["metadata[organization_id]"]).toBe(organizationId)
    expect(checkout.form["line_items[0][price]"]).toBe(stripeStubConfig.offers[0]!.priceId)
    expect(recorded.some((call) => call.method === "GET" && call.path.startsWith("/v1/subscriptions/"))).toBe(true)
    expect(recorded.some((call) => call.path === "/v1/billing_portal/sessions")).toBe(true)
  })

  test("a non-manager sees offers but no checkout or portal", async ({ page, api, user, createUser }) => {
    const owner = await createUser()
    await api.call(
      routes.apiV1SettingsInvitations.create(),
      { email: user.user.email, role: "member", access: "full" },
      owner.token,
    )
    const path = await api.mailLink(user.user.email, "/invitations/")
    await signedIn(page, user, path)
    await page.getByRole("button", { name: text("invitation.accept"), exact: true }).click()
    await expect(page).toHaveURL(/\/dashboard$/)
    const members = await api.call<Membership[]>(routes.apiV1SettingsMembers.index(), undefined, user.token)
    expect(members.find((member) => member.user?.id === user.user.id)?.role).toBe("member")
    const overview = await api.call<BillingOverview>(routes.apiV1SettingsBilling.show(), undefined, user.token)
    expect(overview.canManage).toBe(false)
    await page.goto("/settings/billing")
    await expect(page.getByText(text("billing.read_only"), { exact: true })).toBeVisible()
    await expect(page.getByRole("radio")).toHaveCount(overview.offers.length)
    await expect(page.getByRole("radio").first()).toBeDisabled()
    await expect(page.getByRole("checkbox")).toHaveCount(0)
    await expect(
      page.getByRole("button", { name: new RegExp(text("billing.checkout.submit").split(" (")[0]!) }),
    ).toHaveCount(0)
    await expect(page.getByRole("button", { name: text("billing.portal.open"), exact: true })).toHaveCount(0)
    const forbidden = await api.context.post(routes.apiV1SettingsBillingCheckoutSessions.create().url, {
      headers: { Authorization: `Bearer ${user.token}` },
      data: { offerId: overview.offers[0]!.id, offerRevision: overview.offerRevision, accepted: true },
    })
    expect(forbidden.status()).toBe(403)
    expect((await forbidden.json()).error.code).toBe("forbidden")
  })
})
