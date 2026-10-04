import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { api } from "../http"
import { apiV1SettingsOrganization, apiV1SettingsMembers, apiV1SettingsInvitations } from "../generated/routes"
import type { Organization, OrganizationSettings, Membership, Invitation } from "../generated/serializers"
import { qk } from "../query-keys"
import { useAppConfig } from "./bootstrap"
import { refreshOrganization } from "./organizations"
import type { OrganizationInput, MembershipInput, InvitationInput } from "@/schemas/organizations"

export const isManager = (membership: Membership) =>
  membership.access === "full" && ["owner", "admin"].includes(membership.role)
function useOrganizationKeys() {
  const { auth } = useAppConfig()
  return {
    auth: auth!,
    settings: qk.organization(auth!.organization.id, "settings"),
    members: qk.organization(auth!.organization.id, "members"),
    invitations: qk.organization(auth!.organization.id, "invitations"),
  }
}
export function useOrganizationSettings() {
  const keys = useOrganizationKeys()
  return useQuery({
    queryKey: keys.settings,
    queryFn: async ({ signal }) =>
      (await api.get<OrganizationSettings>(apiV1SettingsOrganization.show(), { signal })).data,
    retry: false,
  })
}
export function useUpdateOrganization() {
  const qc = useQueryClient()
  const keys = useOrganizationKeys()
  return useMutation({
    mutationFn: async (input: OrganizationInput) =>
      (await api.put<Organization>(apiV1SettingsOrganization.update(), input)).data,
    onSuccess: async () => {
      await Promise.all([
        qc.invalidateQueries({ queryKey: keys.settings }),
        qc.invalidateQueries({ queryKey: qk.bootstrap }),
      ])
    },
  })
}
export function useMembers() {
  const keys = useOrganizationKeys()
  return useQuery({
    queryKey: keys.members,
    queryFn: async ({ signal }) => (await api.get<Membership[]>(apiV1SettingsMembers.index(), { signal })).data,
    retry: false,
  })
}
export function useUpdateMembership() {
  const qc = useQueryClient()
  const keys = useOrganizationKeys()
  return useMutation({
    mutationFn: async ({ id, ...input }: MembershipInput & { id: string }) =>
      (await api.put<Membership>(apiV1SettingsMembers.update(id), input)).data,
    onSuccess: async () => {
      await Promise.all([
        qc.invalidateQueries({ queryKey: keys.members }),
        qc.invalidateQueries({ queryKey: qk.bootstrap }),
        qc.invalidateQueries({ queryKey: qk.accountDeletion }),
      ])
    },
  })
}
export function useRemoveMembership() {
  const qc = useQueryClient()
  const keys = useOrganizationKeys()
  return useMutation({
    mutationFn: async (id: string) => {
      await api.del(apiV1SettingsMembers.destroy(id))
      return id
    },
    onSuccess: async (id) => {
      if (id === keys.auth.membership.id) await refreshOrganization(qc)
      else
        await Promise.all([
          qc.invalidateQueries({ queryKey: keys.members }),
          qc.invalidateQueries({ queryKey: qk.accountDeletion }),
        ])
    },
  })
}
export function usePendingInvitations() {
  const keys = useOrganizationKeys()
  return useQuery({
    queryKey: keys.invitations,
    queryFn: async ({ signal }) => (await api.get<Invitation[]>(apiV1SettingsInvitations.index(), { signal })).data,
    enabled: isManager(keys.auth.membership),
    retry: false,
  })
}
export function useInvitePerson() {
  const qc = useQueryClient()
  const keys = useOrganizationKeys()
  return useMutation({
    mutationFn: async (input: InvitationInput) =>
      (await api.post<Invitation>(apiV1SettingsInvitations.create(), input)).data,
    onSuccess: async () => {
      await qc.invalidateQueries({ queryKey: keys.invitations })
    },
  })
}
export function useRevokeInvitation() {
  const qc = useQueryClient()
  const keys = useOrganizationKeys()
  return useMutation({
    mutationFn: async (id: string) => {
      await api.del(apiV1SettingsInvitations.destroy(id))
    },
    onSuccess: async () => {
      await qc.invalidateQueries({ queryKey: keys.invitations })
    },
  })
}
