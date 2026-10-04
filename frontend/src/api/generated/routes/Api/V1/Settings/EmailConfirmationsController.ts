import type { RouteDefinition, RouteOptions } from "../../../runtime"
import { buildUrl } from "../../../runtime"

export default {
  /** GET /api/v1/settings/email-confirmations/:token */
  show: (params: { token: string } | string | number, options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/settings/email-confirmations/:token", params, options),
    method: "get",
  }),
  /** POST /api/v1/settings/email-confirmations */
  create: (options?: RouteOptions): RouteDefinition<"post"> => ({
    url: buildUrl("/api/v1/settings/email-confirmations", {}, options),
    method: "post",
  }),
}
