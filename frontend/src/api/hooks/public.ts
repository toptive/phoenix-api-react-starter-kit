import { useQuery } from "@tanstack/react-query"
import { api } from "../http"
import { apiV1LegalPage, apiV1Event } from "../generated/routes"
import type { LegalPage } from "../generated/serializers"
import { qk } from "../query-keys"
export const useLegalPage = (slug: string, locale: string) =>
  useQuery({
    queryKey: qk.legal(slug, locale),
    queryFn: async ({ signal }) =>
      (await api.get<LegalPage>(apiV1LegalPage.show(slug, { query: { locale } }), { signal })).data,
    retry: false,
  })
export const recordPageView = (page: string) =>
  api.post(apiV1Event.create(), { name: "page_viewed", properties: { page } })
