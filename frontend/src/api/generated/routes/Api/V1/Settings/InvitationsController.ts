import type { RouteDefinition, RouteOptions } from "../../../runtime"
import { buildUrl } from "../../../runtime"

export default {
  /** GET /api/v1/settings/invitations */
  index: (options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/settings/invitations", {}, options),
    method: "get",
  }),
  /** POST /api/v1/settings/invitations */
  create: (options?: RouteOptions): RouteDefinition<"post"> => ({
    url: buildUrl("/api/v1/settings/invitations", {}, options),
    method: "post",
  }),
  /** DELETE /api/v1/settings/invitations/:id */
  destroy: (params: { id: string } | string | number, options?: RouteOptions): RouteDefinition<"delete"> => ({
    url: buildUrl("/api/v1/settings/invitations/:id", params, options),
    method: "delete",
  }),
}
