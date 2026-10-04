import type { RouteDefinition, RouteOptions } from "../../../runtime"
import { buildUrl } from "../../../runtime"

export default {
  /** POST /api/v1/auth/sudo */
  create: (options?: RouteOptions): RouteDefinition<"post"> => ({
    url: buildUrl("/api/v1/auth/sudo", {}, options),
    method: "post",
  }),
}
