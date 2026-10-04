import type { RouteDefinition, RouteOptions } from "../../../runtime"
import { buildUrl } from "../../../runtime"

export default {
  /** DELETE /api/v1/auth/impersonation */
  destroy: (options?: RouteOptions): RouteDefinition<"delete"> => ({
    url: buildUrl("/api/v1/auth/impersonation", {}, options),
    method: "delete",
  }),
}
