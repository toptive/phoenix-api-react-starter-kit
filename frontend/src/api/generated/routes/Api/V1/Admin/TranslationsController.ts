import type { RouteDefinition, RouteOptions } from "../../../runtime"
import { buildUrl } from "../../../runtime"

export default {
  /** GET /api/v1/admin/translations */
  index: (options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/admin/translations", {}, options),
    method: "get",
  }),
  /** PUT /api/v1/admin/translations/:key */
  update: (params: { key: string } | string | number, options?: RouteOptions): RouteDefinition<"put"> => ({
    url: buildUrl("/api/v1/admin/translations/:key", params, options),
    method: "put",
  }),
}
