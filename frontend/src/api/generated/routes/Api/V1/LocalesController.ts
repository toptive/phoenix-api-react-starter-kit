import type { RouteDefinition, RouteOptions } from "../../runtime"
import { buildUrl } from "../../runtime"

export default {
  /** GET /api/v1/locales/:locale */
  show: (params: { locale: string } | string | number, options?: RouteOptions): RouteDefinition<"get"> => ({
    url: buildUrl("/api/v1/locales/:locale", params, options),
    method: "get",
  }),
}
