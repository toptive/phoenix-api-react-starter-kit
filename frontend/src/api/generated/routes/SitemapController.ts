import type { RouteDefinition, RouteOptions } from "./runtime"
import { buildUrl } from "./runtime"

export default {
  /** GET /sitemap.xml */
  show: (options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/sitemap.xml", {}, options),
    method: "get",
  }),
}
