import type { RouteDefinition, RouteOptions } from "../../runtime"
import { buildUrl } from "../../runtime"

export default {
  /** GET /api/v1/bootstrap */
  show: (options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/bootstrap", {}, options),
    method: "get",
  }),
}
