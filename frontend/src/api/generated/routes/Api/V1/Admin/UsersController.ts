import type { RouteDefinition, RouteOptions } from "../../../runtime"
import { buildUrl } from "../../../runtime"

export default {
  /** GET /api/v1/admin/users */
  index: (options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/admin/users", {}, options),
    method: "get",
  }),
  /** GET /api/v1/admin/users/:id */
  show: (params: { id: string } | string | number, options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/admin/users/:id", params, options),
    method: "get",
  }),
  /** PUT /api/v1/admin/users/:id */
  update: (params: { id: string } | string | number, options?: RouteOptions): RouteDefinition<"put"> => ({
    url: buildUrl("/api/v1/admin/users/:id", params, options),
    method: "put",
  }),
}
