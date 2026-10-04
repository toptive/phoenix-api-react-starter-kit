import type { RouteDefinition, RouteOptions } from "../../runtime"
import { buildUrl } from "../../runtime"

export default {
  /** GET /api/v1/onboarding */
  show: (options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/onboarding", {}, options),
    method: "get",
  }),
  /** PUT /api/v1/onboarding */
  update: (options?: RouteOptions): RouteDefinition<"put"> => ({
    url: buildUrl("/api/v1/onboarding", {}, options),
    method: "put",
  }),
}
