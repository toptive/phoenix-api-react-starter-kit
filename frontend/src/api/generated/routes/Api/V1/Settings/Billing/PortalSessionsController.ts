import type { RouteDefinition, RouteOptions } from "../../../../runtime"
import { buildUrl } from "../../../../runtime"

export default {
  /** POST /api/v1/settings/billing/portal-session */
  create: (options?: RouteOptions): RouteDefinition<"post"> => ({
    url: buildUrl("/api/v1/settings/billing/portal-session", {}, options),
    method: "post",
  }),
}
