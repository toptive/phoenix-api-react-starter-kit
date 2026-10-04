import { useMutation, useQuery, useQueryClient, keepPreviousData, type QueryClient } from "@tanstack/react-query"
import { api, getToken, ADMIN_TOKEN_KEY } from "../http"
import {
  apiV1AdminJobsAccess,
  apiV1AdminDashboard,
  apiV1AdminUsers,
  apiV1AdminUsersImpersonation,
  apiV1AdminOrganizations,
  apiV1AdminTranslations,
  apiV1AdminTranslationFills,
  apiV1AdminLegalDocuments,
  apiV1AdminLegalDocumentsVersions,
  apiV1AdminLegalDocumentsVersionsPublication,
  apiV1AdminAuditEvents,
} from "../generated/routes"
import type {
  JobsAccess,
  AdminStats,
  User,
  AdminUserDetail,
  AuthSession,
  AdminOrganization,
  AdminOrganizationDetail,
  TranslationEntry,
  TranslationFill,
  LegalDocument,
  LegalDocumentVersion,
  AuditEvent,
} from "../generated/serializers"
import { qk } from "../query-keys"
import { acceptSession } from "./auth"
import { bootstrapOptions } from "./bootstrap"
import { localeOptions } from "./locales"
import { i18n } from "@/i18n"
import type { ListSearch, TranslationSearch } from "@/schemas/search"
import type { ImpersonationInput, LegalVersionInput, TranslationInput } from "@/schemas/admin"

export const useAdminStats = () =>
  useQuery({
    queryKey: qk.adminStats,
    queryFn: async ({ signal }) => (await api.get<AdminStats>(apiV1AdminDashboard.show(), { signal })).data,
  })
export const useAdminUsers = (search: ListSearch) =>
  useQuery({
    queryKey: qk.adminUsers(search),
    queryFn: ({ signal }) => api.get<User[]>(apiV1AdminUsers.index({ query: search }), { signal }),
    placeholderData: keepPreviousData,
  })
export const useAdminUser = (id: string) =>
  useQuery({
    queryKey: qk.adminUser(id),
    queryFn: async ({ signal }) => (await api.get<AdminUserDetail>(apiV1AdminUsers.show(id), { signal })).data,
  })
export function useUpdateAdminUser(id: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (role: User["role"]) => (await api.put<User>(apiV1AdminUsers.update(id), { role })).data,
    onSuccess: async () => {
      await Promise.all([
        qc.invalidateQueries({ queryKey: ["admin", "users"] }),
        qc.invalidateQueries({ queryKey: qk.bootstrap }),
        qc.invalidateQueries({ queryKey: qk.adminAuditRoot }),
      ])
    },
  })
}
export function useImpersonate(id: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: ImpersonationInput) => {
      const admin = getToken()
      const session = (await api.post<AuthSession>(apiV1AdminUsersImpersonation.create(id), input)).data
      if (!admin || !session.token || !session.impersonator) throw new Error("Invalid impersonation session")
      localStorage.setItem(ADMIN_TOKEN_KEY, admin)
      return session
    },
    onSuccess: (session) => acceptSession(qc, session),
  })
}
export const useAdminOrganizations = (search: ListSearch) =>
  useQuery({
    queryKey: qk.adminOrganizations(search),
    queryFn: ({ signal }) => api.get<AdminOrganization[]>(apiV1AdminOrganizations.index({ query: search }), { signal }),
    placeholderData: keepPreviousData,
  })
export const useAdminOrganization = (id: string) =>
  useQuery({
    queryKey: qk.adminOrganization(id),
    queryFn: async ({ signal }) =>
      (await api.get<AdminOrganizationDetail>(apiV1AdminOrganizations.show(id), { signal })).data,
  })
export const useAdminTranslations = (search: TranslationSearch) =>
  useQuery({
    queryKey: qk.adminTranslations(search),
    queryFn: ({ signal }) => api.get<TranslationEntry[]>(apiV1AdminTranslations.index({ query: search }), { signal }),
    placeholderData: keepPreviousData,
  })
async function refreshTranslations(qc: QueryClient) {
  await Promise.all([
    qc.invalidateQueries({ queryKey: qk.adminTranslationsRoot }),
    qc.invalidateQueries({ queryKey: qk.adminAuditRoot }),
    qc.invalidateQueries({ queryKey: qk.bootstrap }),
  ])
  const bootstrap = await qc.fetchQuery(bootstrapOptions())
  // A new version and a forced revalidation both cover backends returning the same version.
  await qc.fetchQuery({ ...localeOptions(i18n.language, bootstrap.i18nVersion), staleTime: 0 })
  await qc.invalidateQueries({ queryKey: ["locale"] })
}
export function useUpdateTranslation() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ key, ...input }: TranslationInput & { key: string }) =>
      (await api.put<TranslationEntry>(apiV1AdminTranslations.update(key), input)).data,
    onSuccess: () => refreshTranslations(qc),
  })
}
export function useFillTranslations() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (locale: string) =>
      (await api.post<TranslationFill>(apiV1AdminTranslationFills.create(), { locale })).data,
    onSuccess: () => refreshTranslations(qc),
  })
}
export const useLegalDocuments = () =>
  useQuery({
    queryKey: qk.adminLegalRoot,
    queryFn: async ({ signal }) => (await api.get<LegalDocument[]>(apiV1AdminLegalDocuments.index(), { signal })).data,
  })
export const useLegalDocument = (slug: string) =>
  useQuery({
    queryKey: qk.adminLegal(slug),
    queryFn: async ({ signal }) => (await api.get<LegalDocument>(apiV1AdminLegalDocuments.show(slug), { signal })).data,
  })
async function refreshLegal(qc: QueryClient) {
  await Promise.all([
    qc.invalidateQueries({ queryKey: qk.adminLegalRoot }),
    qc.invalidateQueries({ queryKey: ["legal"] }),
    qc.invalidateQueries({ queryKey: qk.adminAuditRoot }),
  ])
}
export function useCreateLegalVersion(slug: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: LegalVersionInput) =>
      (await api.post<LegalDocumentVersion>(apiV1AdminLegalDocumentsVersions.create(slug), input)).data,
    onSuccess: () => refreshLegal(qc),
  })
}
export function usePublishLegalVersion(slug: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (number: number) =>
      (await api.post<LegalDocument>(apiV1AdminLegalDocumentsVersionsPublication.create(slug, number))).data,
    onSuccess: () => refreshLegal(qc),
  })
}
export const useAuditEvents = (search: ListSearch) =>
  useQuery({
    queryKey: qk.adminAudit(search),
    queryFn: ({ signal }) => api.get<AuditEvent[]>(apiV1AdminAuditEvents.index({ query: search }), { signal }),
    placeholderData: keepPreviousData,
  })

export const useJobsAccess = () =>
  useMutation({
    mutationFn: async () => (await api.post<JobsAccess>(apiV1AdminJobsAccess.create())).data,
  })
