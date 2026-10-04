import type { RouteDefinition, RouteOptions } from "../../../runtime"
import { buildUrl } from "../../../runtime"

export default {
  /** GET /api/v1/settings/sessions */
  index: (options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/settings/sessions", {}, options),
    method: "get",
  }),
  /** DELETE /api/v1/settings/sessions/:id */
  destroy: (params: { id: string } | string | number, options?: RouteOptions): RouteDefinition<"delete"> => ({
    url: buildUrl("/api/v1/settings/sessions/:id", params, options),
    method: "delete",
  }),
}
