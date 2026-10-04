import type { RouteDefinition, RouteOptions } from "../../../runtime"
import { buildUrl } from "../../../runtime"

export default {
  /** POST /api/v1/invitations/:token/acceptance */
  create: (params: { token: string } | string | number, options?: RouteOptions): RouteDefinition<"post"> => ({
    url: buildUrl("/api/v1/invitations/:token/acceptance", params, options),
    method: "post",
  }),
}
