import { createHmac, randomUUID } from "node:crypto"
import { createServer } from "node:http"

// These are local fixtures, never credentials for a Stripe account.
export const stripeStubConfig = {
  url: process.env.E2E_STRIPE_URL ?? "http://127.0.0.1:4242",
  secret: process.env.STRIPE_TEST_WEBHOOK_SECRET ?? "whsec_test_fake",
  offers: JSON.parse(
    process.env.E2E_STRIPE_OFFERS ??
      JSON.stringify([
        {
          id: "pro_monthly",
          priceId: process.env.STRIPE_TEST_PRICE_PRO_MONTHLY ?? "price_test_monthly",
          amountCents: 1900,
          currency: "usd",
          interval: "month",
        },
        {
          id: "pro_yearly",
          priceId: process.env.STRIPE_TEST_PRICE_PRO_YEARLY ?? "price_test_yearly",
          amountCents: 19000,
          currency: "usd",
          interval: "year",
        },
      ]),
  ),
}

/** Stub only Stripe's upstream HTTP. Browser requests still reach the real API. */
export async function startStripeStub() {
  const apiURL = process.env.E2E_API_URL ?? "http://localhost:4100"
  const spaURL = process.env.E2E_BASE_URL ?? `http://localhost:${process.env.E2E_VITE_PORT ?? "5174"}`
  const sessions = new Map()
  const subscriptions = new Map()
  const calls = []
  const price = (offer) => ({
    id: offer.priceId,
    object: "price",
    active: true,
    livemode: false,
    unit_amount: offer.amountCents,
    currency: offer.currency,
    recurring: { interval: offer.interval },
  })
  const server = createServer(async (request, response) => {
    const send = (status, data) => {
      response.writeHead(status, { "content-type": "application/json" })
      response.end(JSON.stringify(data))
    }
    try {
      const path = new URL(request.url, stripeStubConfig.url).pathname
      const chunks = []
      for await (const chunk of request) chunks.push(chunk)
      const raw = Buffer.concat(chunks).toString()
      if (request.method === "GET" && path === "/__stub/health") return send(200, { ready: true })
      if (request.method === "GET" && path === "/__stub/calls") return send(200, { calls })
      if (request.method === "GET" && (path.startsWith("/checkout/") || path.startsWith("/portal/"))) {
        const returnPath = path.startsWith("/checkout/") ? "/settings/billing?checkout=done" : "/settings/billing"
        response.writeHead(302, { location: new URL(returnPath, spaURL).href })
        return response.end()
      }
      const form = new URLSearchParams(raw)
      if (path.startsWith("/v1/")) calls.push({ method: request.method, path, form: Object.fromEntries(form) })
      if (request.method === "GET" && path.startsWith("/v1/prices/")) {
        const offer = stripeStubConfig.offers.find((offer) => offer.priceId === path.split("/").at(-1))
        return offer ? send(200, price(offer)) : send(404, { error: { code: "unknown_price" } })
      }
      if (request.method === "POST" && path === "/v1/checkout/sessions") {
        const organizationId = form.get("metadata[organization_id]")
        const offer = stripeStubConfig.offers.find((offer) => offer.priceId === form.get("line_items[0][price]"))
        if (!organizationId || !offer) return send(400, { error: { code: "invalid_checkout" } })
        const id = `cs_test_${randomUUID()}`
        const subscriptionId = `sub_${randomUUID()}`
        const subscription = {
          id: subscriptionId,
          object: "subscription",
          livemode: false,
          customer: `cus_${randomUUID()}`,
          status: "active",
          cancel_at_period_end: false,
          pause_collection: null,
          metadata: { organization_id: organizationId, offer_id: offer.id },
          items: { data: [{ price: price(offer), current_period_end: Math.floor(Date.now() / 1000) + 86400 * 30 }] },
        }
        subscriptions.set(subscriptionId, subscription)
        sessions.set(organizationId, {
          id,
          object: "checkout.session",
          subscription: subscriptionId,
          metadata: subscription.metadata,
        })
        return send(200, { id, url: new URL(`/checkout/${id}`, stripeStubConfig.url).href })
      }
      if (request.method === "GET" && path.startsWith("/v1/subscriptions/")) {
        const subscription = subscriptions.get(path.split("/").at(-1))
        return subscription ? send(200, subscription) : send(404, { error: { code: "unknown_subscription" } })
      }
      if (request.method === "POST" && path === "/v1/billing_portal/sessions") {
        if (![...subscriptions.values()].some((subscription) => subscription.customer === form.get("customer")))
          return send(400, { error: { code: "unknown_customer" } })
        const id = `bps_${randomUUID()}`
        return send(200, { id, url: new URL(`/portal/${id}`, stripeStubConfig.url).href })
      }
      if (request.method === "POST" && path === "/__stub/webhook") {
        const { organizationId } = JSON.parse(raw)
        const session = sessions.get(organizationId)
        if (!session) return send(404, { error: { code: "unknown_checkout" } })
        const results = []
        for (const [type, object] of [
          ["checkout.session.completed", session],
          ["customer.subscription.created", subscriptions.get(session.subscription)],
        ]) {
          const timestamp = Math.floor(Date.now() / 1000)
          const body = JSON.stringify({
            id: `evt_${randomUUID()}`,
            type,
            livemode: false,
            created: timestamp,
            data: { object },
          })
          const signature = createHmac("sha256", stripeStubConfig.secret).update(`${timestamp}.${body}`).digest("hex")
          const result = await fetch(new URL("/webhooks/stripe/events", apiURL), {
            method: "POST",
            body,
            headers: { "content-type": "application/json", "Stripe-Signature": `t=${timestamp},v1=${signature}` },
          })
          results.push({ type, status: result.status })
          if (!result.ok) return send(502, { results })
        }
        return send(200, { results })
      }
      send(404, { error: { code: "unknown_stub_route" } })
    } catch {
      send(500, { error: { code: "stub_failed" } })
    }
  })
  const url = new URL(stripeStubConfig.url)
  await new Promise((resolve, reject) => {
    server.once("error", reject)
    // Bind localhost to IPv4 so Phoenix and the browser reach the same stub.
    server.listen(Number(url.port), url.hostname === "localhost" ? "127.0.0.1" : url.hostname, resolve)
  })
  return async () => {
    server.closeAllConnections()
    await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())))
  }
}
