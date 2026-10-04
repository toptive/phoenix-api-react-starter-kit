import type { RouteDefinition, RouteOptions } from "../../../runtime"
import { buildUrl } from "../../../runtime"

export default {
  /** GET /api/v1/settings/email-preferences */
  show: (options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/settings/email-preferences", {}, options),
    method: "get",
  }),
  /** PUT /api/v1/settings/email-preferences */
  update: (options?: RouteOptions): RouteDefinition<"put"> => ({
    url: buildUrl("/api/v1/settings/email-preferences", {}, options),
    method: "put",
  }),
}
