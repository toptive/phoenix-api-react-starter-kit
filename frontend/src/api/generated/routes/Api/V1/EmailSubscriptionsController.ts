import type { RouteDefinition, RouteOptions } from "../../runtime"
import { buildUrl } from "../../runtime"

export default {
  /** GET /api/v1/email-subscriptions/:token */
  show: (params: { token: string } | string | number, options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/email-subscriptions/:token", params, options),
    method: "get",
  }),
}
