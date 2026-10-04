import type { RouteDefinition, RouteOptions } from "../../../runtime"
import { buildUrl } from "../../../runtime"

export default {
  /** POST /api/v1/auth/magic-links */
  create: (options?: RouteOptions): RouteDefinition<"post"> => ({
    url: buildUrl("/api/v1/auth/magic-links", {}, options),
    method: "post",
  }),
  /** GET /api/v1/auth/magic-links/:token */
  show: (params: { token: string } | string | number, options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/auth/magic-links/:token", params, options),
    method: "get",
  }),
}
