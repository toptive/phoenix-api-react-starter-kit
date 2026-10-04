import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { api, clearTokens } from "../http"
import {
  apiV1SettingsProfile,
  apiV1SettingsEmailPreferences,
  apiV1SettingsSessions,
  apiV1SettingsEmail,
  apiV1SettingsPassword,
  apiV1SettingsAccount,
} from "../generated/routes"
import type {
  User,
  EmailPreferences,
  Session,
  EmailChange,
  AuthSession,
  AccountDeletion,
} from "../generated/serializers"
import { qk } from "../query-keys"
import { acceptSession } from "./auth"
import { bootstrapOptions, useAppConfig } from "./bootstrap"
import { localeOptions, restoreLocale } from "./locales"
import { useSudoAction } from "@/hooks/use-sudo-action"
import type { ProfileInput, EmailPreferencesInput, ChangeEmailInput, PasswordInput } from "@/schemas/settings"

export function useUpdateProfile() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: ProfileInput) => (await api.put<User>(apiV1SettingsProfile.update(), input)).data,
    onSuccess: async (user) => {
      restoreLocale(user.locale)
      await qc.invalidateQueries({ queryKey: qk.bootstrap })
      const bootstrap = await qc.ensureQueryData(bootstrapOptions())
      await qc.fetchQuery({ ...localeOptions(user.locale, bootstrap.i18nVersion), staleTime: 0 })
    },
  })
}
export function useEmailPreferences() {
  return useQuery({
    queryKey: qk.emailPreferences,
    queryFn: async ({ signal }) =>
      (await api.get<EmailPreferences>(apiV1SettingsEmailPreferences.show(), { signal })).data,
    retry: false,
  })
}
export function useUpdateEmailPreferences() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: EmailPreferencesInput) =>
      (await api.put<EmailPreferences>(apiV1SettingsEmailPreferences.update(), input)).data,
    onSuccess: async () => {
      await qc.invalidateQueries({ queryKey: qk.emailPreferences })
    },
  })
}
export function useSessions() {
  return useQuery({
    queryKey: qk.sessions,
    queryFn: async ({ signal }) => (await api.get<Session[]>(apiV1SettingsSessions.index(), { signal })).data,
    retry: false,
  })
}
export function useRevokeSession() {
  const qc = useQueryClient()
  const { auth } = useAppConfig()
  return useMutation({
    mutationFn: async (id: string) => {
      await api.del(apiV1SettingsSessions.destroy(id))
      return id
    },
    onSuccess: async (id) => {
      if (id === auth?.sessionId) {
        clearTokens()
        await qc.cancelQueries()
        qc.removeQueries()
      } else await qc.invalidateQueries({ queryKey: qk.sessions })
    },
  })
}
export function useChangeEmail() {
  const withSudo = useSudoAction()
  return useMutation({
    mutationFn: (input: ChangeEmailInput) =>
      withSudo(async () => (await api.put<EmailChange>(apiV1SettingsEmail.update(), input)).data),
  })
}
export function useChangePassword() {
  const qc = useQueryClient()
  const withSudo = useSudoAction()
  return useMutation({
    mutationFn: (input: PasswordInput) =>
      withSudo(async () => (await api.put<AuthSession>(apiV1SettingsPassword.update(), input)).data),
    onSuccess: (session) => acceptSession(qc, session),
  })
}
export function useAccountDeletion() {
  const withSudo = useSudoAction()
  return useQuery({
    queryKey: qk.accountDeletion,
    queryFn: ({ signal }) =>
      withSudo(async () => (await api.get<AccountDeletion>(apiV1SettingsAccount.show(), { signal })).data),
    retry: false,
    gcTime: 0,
  })
}
export function useDeleteAccount() {
  const qc = useQueryClient()
  const withSudo = useSudoAction()
  return useMutation({
    mutationFn: () =>
      withSudo(async () => {
        await api.del(apiV1SettingsAccount.destroy())
      }),
    onSuccess: async () => {
      clearTokens()
      await qc.cancelQueries()
      qc.removeQueries()
    },
  })
}
