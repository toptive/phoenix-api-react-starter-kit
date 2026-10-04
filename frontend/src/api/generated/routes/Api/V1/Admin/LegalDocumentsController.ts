import type { RouteDefinition, RouteOptions } from "../../../runtime"
import { buildUrl } from "../../../runtime"

export default {
  /** GET /api/v1/admin/legal-documents */
  index: (options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/admin/legal-documents", {}, options),
    method: "get",
  }),
  /** GET /api/v1/admin/legal-documents/:slug */
  show: (params: { slug: string } | string | number, options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/admin/legal-documents/:slug", params, options),
    method: "get",
  }),
}
