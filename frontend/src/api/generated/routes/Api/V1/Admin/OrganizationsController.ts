import type { RouteDefinition, RouteOptions } from "../../../runtime"
import { buildUrl } from "../../../runtime"

export default {
  /** GET /api/v1/admin/organizations */
  index: (options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/admin/organizations", {}, options),
    method: "get",
  }),
  /** GET /api/v1/admin/organizations/:id */
  show: (params: { id: string } | string | number, options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/admin/organizations/:id", params, options),
    method: "get",
  }),
}
