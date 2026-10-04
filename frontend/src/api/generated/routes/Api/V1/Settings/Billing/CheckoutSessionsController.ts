import type { RouteDefinition, RouteOptions } from "../../../../runtime"
import { buildUrl } from "../../../../runtime"

export default {
  /** POST /api/v1/settings/billing/checkout-session */
  create: (options?: RouteOptions): RouteDefinition<"post"> => ({
    url: buildUrl("/api/v1/settings/billing/checkout-session", {}, options),
    method: "post",
  }),
}
