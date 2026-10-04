import type { RouteDefinition, RouteOptions } from "../../../runtime"
import { buildUrl } from "../../../runtime"

export default {
  /** GET /api/v1/admin/audit-events */
  index: (options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/admin/audit-events", {}, options),
    method: "get",
  }),
}
