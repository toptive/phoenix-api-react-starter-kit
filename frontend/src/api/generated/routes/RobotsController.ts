import type { RouteDefinition, RouteOptions } from "./runtime"
import { buildUrl } from "./runtime"

export default {
  /** GET /robots.txt */
  show: (options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/robots.txt", {}, options),
    method: "get",
  }),
}
