import type { RouteDefinition, RouteOptions } from "../../runtime"
import { buildUrl } from "../../runtime"

export default {
  /** GET /api/v1/legal-pages/:slug */
  show: (params: { slug: string } | string | number, options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/legal-pages/:slug", params, options),
    method: "get",
  }),
}
