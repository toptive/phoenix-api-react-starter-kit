import type { RouteDefinition, RouteOptions } from "../../../runtime"
import { buildUrl } from "../../../runtime"

export default {
  /** POST /api/v1/email-subscriptions/:token/opt-out */
  create: (params: { token: string } | string | number, options?: RouteOptions): RouteDefinition<"post"> => ({
    url: buildUrl("/api/v1/email-subscriptions/:token/opt-out", params, options),
    method: "post",
  }),
}
