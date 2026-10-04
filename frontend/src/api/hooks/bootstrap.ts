import { setSearchLocales } from "@/schemas/search"
import { queryOptions, useQuery } from "@tanstack/react-query"
import { api } from "../http"
import { apiV1Bootstrap } from "../generated/routes"
import type { Bootstrap } from "../generated/serializers"
import { qk } from "../query-keys"

export const bootstrapOptions = () =>
  queryOptions({
    queryKey: qk.bootstrap,
    queryFn: async ({ signal }) => {
      const data = (await api.get<Bootstrap>(apiV1Bootstrap.show(), { signal })).data
      setSearchLocales(data.locales)
      return data
    },
    staleTime: 30_000,
    retry: false,
  })
export const useBootstrap = (enabled = true) => useQuery({ ...bootstrapOptions(), enabled })
/** The shell only renders children after bootstrap. */
export function useAppConfig(): Bootstrap {
  const { data } = useBootstrap()
  if (!data) throw new Error("Bootstrap is not ready")
  return data
}
