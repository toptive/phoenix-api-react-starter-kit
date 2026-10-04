import type { RouteDefinition, RouteOptions } from "../runtime"
import { buildUrl } from "../runtime"

export default {
  /** POST /webhooks/stripe/events */
  create: (options?: RouteOptions): RouteDefinition<"post"> => ({
    url: buildUrl("/webhooks/stripe/events", {}, options),
    method: "post",
  }),
}
