import { useMutation, useQuery, useQueryClient, type QueryClient } from "@tanstack/react-query"
import { api } from "../http"
import { apiV1Organizations, apiV1Onboarding, apiV1Invitations, apiV1InvitationsAcceptance } from "../generated/routes"
import type { Organization, Onboarding, InvitationPreview, Membership, Bootstrap } from "../generated/serializers"
import { qk } from "../query-keys"
import { useAppConfig } from "./bootstrap"
import type { OrganizationInput, OnboardingInput } from "@/schemas/organizations"

/** Current-organization changes must never reuse another tenant's cached data. */
export async function refreshOrganization(qc: QueryClient) {
  await qc.cancelQueries({ queryKey: ["organization"] })
  await qc.invalidateQueries({ queryKey: qk.bootstrap })
  const orgId = qc.getQueryData<Bootstrap>(qk.bootstrap)?.auth?.organization.id
  qc.removeQueries({ queryKey: ["organization"], predicate: (query) => query.queryKey[1] !== orgId })
  await qc.invalidateQueries({ queryKey: ["organization", orgId] })
  await qc.invalidateQueries({ queryKey: ["invitation"] })
  await qc.invalidateQueries({ queryKey: qk.accountDeletion })
}
export function useCreateOrganization() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: OrganizationInput) =>
      (await api.post<Organization>(apiV1Organizations.create(), input)).data,
    onSuccess: () => refreshOrganization(qc),
  })
}
export function useOnboarding() {
  const { auth } = useAppConfig()
  return useQuery({
    queryKey: qk.organization(auth!.organization.id, "onboarding"),
    queryFn: async ({ signal }) => (await api.get<Onboarding>(apiV1Onboarding.show(), { signal })).data,
    retry: false,
  })
}
export function useCompleteOnboarding() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: OnboardingInput) => (await api.put<Organization>(apiV1Onboarding.update(), input)).data,
    onSuccess: () => refreshOrganization(qc),
  })
}
export function useInvitation(token: string) {
  const { auth } = useAppConfig()
  return useQuery({
    queryKey: qk.invitation(token, auth?.user.id ?? "guest"),
    queryFn: async ({ signal }) => (await api.get<InvitationPreview>(apiV1Invitations.show(token), { signal })).data,
    enabled: Boolean(token),
    retry: false,
    gcTime: 0,
  })
}
export function useAcceptInvitation() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (token: string) => (await api.post<Membership>(apiV1InvitationsAcceptance.create(token))).data,
    onSuccess: () => refreshOrganization(qc),
  })
}
