import type { RouteDefinition, RouteOptions } from "../../../runtime"
import { buildUrl } from "../../../runtime"

export default {
  /** GET /api/v1/settings/account */
  show: (options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/settings/account", {}, options),
    method: "get",
  }),
  /** DELETE /api/v1/settings/account */
  destroy: (options?: RouteOptions): RouteDefinition<"delete"> => ({
    url: buildUrl("/api/v1/settings/account", {}, options),
    method: "delete",
  }),
}
