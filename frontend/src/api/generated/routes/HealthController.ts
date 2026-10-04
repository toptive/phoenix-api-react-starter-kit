import type { RouteDefinition, RouteOptions } from "./runtime"
import { buildUrl } from "./runtime"

export default {
  /** GET /health */
  show: (options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/health", {}, options),
    method: "get",
  }),
}
