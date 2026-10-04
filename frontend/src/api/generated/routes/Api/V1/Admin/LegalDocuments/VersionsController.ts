import type { RouteDefinition, RouteOptions } from "../../../../runtime"
import { buildUrl } from "../../../../runtime"

export default {
  /** POST /api/v1/admin/legal-documents/:slug/versions */
  create: (params: { slug: string } | string | number, options?: RouteOptions): RouteDefinition<"post"> => ({
    url: buildUrl("/api/v1/admin/legal-documents/:slug/versions", params, options),
    method: "post",
  }),
}
