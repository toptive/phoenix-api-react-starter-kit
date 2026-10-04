import type { RouteDefinition, RouteOptions } from "../../../../runtime"
import { buildUrl } from "../../../../runtime"

export default {
  /** POST /api/v1/auth/magic-links/:token/session */
  create: (params: { token: string } | string | number, options?: RouteOptions): RouteDefinition<"post"> => ({
    url: buildUrl("/api/v1/auth/magic-links/:token/session", params, options),
    method: "post",
  }),
}
