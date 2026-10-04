import type { RouteDefinition, RouteOptions } from "../../runtime"
import { buildUrl } from "../../runtime"

export default {
  /** POST /api/v1/direct-uploads */
  create: (options?: RouteOptions): RouteDefinition<"post"> => ({
    url: buildUrl("/api/v1/direct-uploads", {}, options),
    method: "post",
  }),
}
