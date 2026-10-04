import { useState } from "react"
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { api, ApiError } from "../http"
import {
  apiV1SettingsBilling,
  apiV1SettingsBillingCheckoutSessions,
  apiV1SettingsBillingPortalSessions,
} from "../generated/routes"
import type { BillingOverview, RedirectUrl } from "../generated/serializers"
import { useAppConfig } from "./bootstrap"
import { qk } from "../query-keys"
import type { CheckoutInput } from "@/schemas/billing"
export function useBilling(confirming = false) {
  const [startedAt] = useState(() => Date.now())
  const { auth } = useAppConfig()
  return useQuery({
    queryKey: qk.organization(auth!.organization.id, "billing"),
    queryFn: async ({ signal }) => (await api.get<BillingOverview>(apiV1SettingsBilling.show(), { signal })).data,
    retry: false,
    refetchInterval: (query) =>
      confirming && !query.state.data?.subscription?.paid && Date.now() - startedAt < 60_000 ? 3_000 : false,
  })
}
export function useCheckout() {
  const qc = useQueryClient()
  const { auth } = useAppConfig()
  return useMutation({
    mutationFn: async (input: CheckoutInput) =>
      (await api.post<RedirectUrl>(apiV1SettingsBillingCheckoutSessions.create(), input)).data,
    onSuccess: async () => {
      await Promise.all([
        qc.invalidateQueries({ queryKey: qk.organization(auth!.organization.id, "billing") }),
        qc.invalidateQueries({ queryKey: qk.adminAuditRoot }),
      ])
    },
    onError: async (error) => {
      if (error instanceof ApiError && ["offer_changed", "already_subscribed"].includes(error.code))
        await qc.invalidateQueries({ queryKey: qk.organization(auth!.organization.id, "billing") })
    },
  })
}
export function useBillingPortal() {
  const qc = useQueryClient()
  const { auth } = useAppConfig()
  return useMutation({
    mutationFn: async () => (await api.post<RedirectUrl>(apiV1SettingsBillingPortalSessions.create())).data,
    onSuccess: async () => {
      await Promise.all([
        qc.invalidateQueries({ queryKey: qk.organization(auth!.organization.id, "billing") }),
        qc.invalidateQueries({ queryKey: qk.adminAuditRoot }),
      ])
    },
  })
}
