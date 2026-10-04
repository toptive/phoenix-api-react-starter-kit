import type { RouteDefinition, RouteOptions } from "../../../../../runtime"
import { buildUrl } from "../../../../../runtime"

export default {
  /** POST /api/v1/admin/legal-documents/:slug/versions/:number/publication */
  create: (params: { slug: string; number: string | number }, options?: RouteOptions): RouteDefinition<"post"> => ({
    url: buildUrl("/api/v1/admin/legal-documents/:slug/versions/:number/publication", params, options),
    method: "post",
  }),
}
