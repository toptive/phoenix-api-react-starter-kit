import type { RouteDefinition, RouteOptions } from "../../runtime"
import { buildUrl } from "../../runtime"

export default {
  /** PUT /api/v1/current-organization */
  update: (options?: RouteOptions): RouteDefinition<"put"> => ({
    url: buildUrl("/api/v1/current-organization", {}, options),
    method: "put",
  }),
}
