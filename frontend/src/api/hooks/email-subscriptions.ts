import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { api } from "../http"
import { apiV1EmailSubscriptions, apiV1EmailSubscriptionsOptOut } from "../generated/routes"
import type { EmailSubscription } from "../generated/serializers"
import { qk } from "../query-keys"

const key = (token: string) => ["email-subscription", token] as const
export function useEmailSubscription(token: string) {
  return useQuery({
    queryKey: key(token),
    queryFn: async ({ signal }) =>
      (await api.get<EmailSubscription>(apiV1EmailSubscriptions.show(token), { signal })).data,
    retry: false,
  })
}
export function useOptOut(token: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async () => (await api.post<EmailSubscription>(apiV1EmailSubscriptionsOptOut.create(token))).data,
    onSuccess: async (subscription) => {
      qc.setQueryData(key(token), subscription)
      await qc.invalidateQueries({ queryKey: qk.emailPreferences })
    },
  })
}
