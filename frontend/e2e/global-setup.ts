import { request } from "@playwright/test"
import { seedUser } from "./backend"

export default async function setup() {
  const api = await request.newContext({ baseURL: process.env.E2E_API_URL ?? "http://localhost:4100" })
  try {
    const mailbox = await api.get("/dev/mailbox")
    const csrf = (await mailbox.text()).match(/name="_csrf_token"[^>]*value="([^"]+)"/)?.[1]
    // Swoosh omits the clear form when its mailbox is already empty.
    if (csrf) {
      const response = await api.post(process.env.E2E_MAILBOX_CLEAR_PATH ?? "/dev/mailbox/clear", {
        form: { _csrf_token: csrf },
      })
      if (!response.ok()) throw new Error(`Mailbox clear failed: ${response.status()}`)
    }
    const remaining = await api.get(process.env.E2E_MAILBOX_PATH ?? "/dev/mailbox/json")
    if ((await remaining.json()).data.length) throw new Error("Mailbox was not cleared")
    seedUser("e2e-superadmin@example.com", true)
  } finally {
    await api.dispose()
  }
}
