import type { RouteDefinition, RouteOptions } from "../../../runtime"
import { buildUrl } from "../../../runtime"

export default {
  /** GET /api/v1/settings/organization */
  show: (options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/settings/organization", {}, options),
    method: "get",
  }),
  /** PUT /api/v1/settings/organization */
  update: (options?: RouteOptions): RouteDefinition<"put"> => ({
    url: buildUrl("/api/v1/settings/organization", {}, options),
    method: "put",
  }),
}
