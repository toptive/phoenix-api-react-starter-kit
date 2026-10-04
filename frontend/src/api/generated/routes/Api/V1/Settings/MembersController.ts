import type { RouteDefinition, RouteOptions } from "../../../runtime"
import { buildUrl } from "../../../runtime"

export default {
  /** GET /api/v1/settings/members */
  index: (options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/settings/members", {}, options),
    method: "get",
  }),
  /** PUT /api/v1/settings/members/:id */
  update: (params: { id: string } | string | number, options?: RouteOptions): RouteDefinition<"put"> => ({
    url: buildUrl("/api/v1/settings/members/:id", params, options),
    method: "put",
  }),
  /** DELETE /api/v1/settings/members/:id */
  destroy: (params: { id: string } | string | number, options?: RouteOptions): RouteDefinition<"delete"> => ({
    url: buildUrl("/api/v1/settings/members/:id", params, options),
    method: "delete",
  }),
}
