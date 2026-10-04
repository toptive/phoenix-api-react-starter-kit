import type { RouteDefinition, RouteOptions } from "../../../../runtime"
import { buildUrl } from "../../../../runtime"

export default {
  /** POST /api/v1/admin/users/:id/impersonation */
  create: (params: { id: string } | string | number, options?: RouteOptions): RouteDefinition<"post"> => ({
    url: buildUrl("/api/v1/admin/users/:id/impersonation", params, options),
    method: "post",
  }),
}
