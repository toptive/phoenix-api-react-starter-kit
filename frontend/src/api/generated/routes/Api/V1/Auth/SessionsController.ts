import type { RouteDefinition, RouteOptions } from "../../../runtime"
import { buildUrl } from "../../../runtime"

export default {
  /** POST /api/v1/auth/sessions */
  create: (options?: RouteOptions): RouteDefinition<"post"> => ({
    url: buildUrl("/api/v1/auth/sessions", {}, options),
    method: "post",
  }),
  /** DELETE /api/v1/auth/session */
  destroy: (options?: RouteOptions): RouteDefinition<"delete"> => ({
    url: buildUrl("/api/v1/auth/session", {}, options),
    method: "delete",
  }),
}
