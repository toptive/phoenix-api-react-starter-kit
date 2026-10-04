import type { RouteDefinition, RouteOptions } from "../../../../runtime"
import { buildUrl } from "../../../../runtime"

export default {
  /** GET /api/v1/auth/google/start */
  show: (options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/auth/google/start", {}, options),
    method: "get",
  }),
}
