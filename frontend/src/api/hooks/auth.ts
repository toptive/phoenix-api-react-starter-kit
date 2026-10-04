import { useMutation, useQuery, useQueryClient, type QueryClient } from "@tanstack/react-query"
import { api, setToken, clearTokens, ADMIN_TOKEN_KEY } from "../http"
import {
  apiV1AuthSessions,
  apiV1AuthMagicLinks,
  apiV1AuthMagicLinksSessions,
  apiV1AuthRegistrations,
  apiV1AuthSudo,
  apiV1AuthGoogleStart,
  apiV1SettingsEmailConfirmations,
  apiV1CurrentOrganization,
  apiV1AuthImpersonation,
} from "../generated/routes"
import type {
  AuthSession,
  MagicLink,
  MagicLinkRequest,
  SudoWindow,
  EmailChange,
  User,
  Auth,
} from "../generated/serializers"
import { qk } from "../query-keys"
import { bootstrapOptions, useBootstrap } from "./bootstrap"
import type { SignInInput, MagicLinkInput, RegistrationInput } from "@/schemas/auth"
import { refreshOrganization } from "./organizations"
import { safeReturnPath } from "@/lib/auth-flow"

export async function acceptSession(qc: QueryClient, session: AuthSession) {
  await qc.cancelQueries()
  if (session.token) {
    if (!session.impersonator) clearTokens()
    setToken(session.token)
  }
  qc.removeQueries()
  await qc.fetchQuery(bootstrapOptions())
}
export function useSignIn() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: SignInInput) =>
      (await api.post<AuthSession>(apiV1AuthSessions.create(), input, { anonymous: true })).data,
    onSuccess: (session) => acceptSession(qc, session),
  })
}
export const useCurrentUser = () => useBootstrap().data?.auth?.user ?? null
export const useRequestMagicLink = () =>
  useMutation({
    mutationFn: async (input: MagicLinkInput) =>
      (await api.post<MagicLinkRequest>(apiV1AuthMagicLinks.create(), input)).data,
  })
export const useRegister = () =>
  useMutation({
    mutationFn: async (input: RegistrationInput) =>
      (await api.post<MagicLinkRequest>(apiV1AuthRegistrations.create(), input)).data,
  })
export function useMagicLink(token: string) {
  return useQuery({
    queryKey: qk.magicLink(token),
    queryFn: async () => (await api.get<MagicLink>(apiV1AuthMagicLinks.show(token))).data,
    enabled: Boolean(token),
    retry: false,
    gcTime: 0,
  })
}
export function useConsumeMagicLink() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (token: string) => (await api.post<AuthSession>(apiV1AuthMagicLinksSessions.create(token))).data,
    onSuccess: (session) => acceptSession(qc, session),
  })
}
/** A first magic-link session confirms the address as well as signing in. */
export const useConfirmEmail = useConsumeMagicLink
export function useSudo() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { password: string } | { magicLinkToken: string }) =>
      (await api.post<SudoWindow>(apiV1AuthSudo.create(), input)).data,
    onSuccess: async () => {
      await qc.invalidateQueries({ queryKey: qk.bootstrap })
    },
  })
}
export function useSignOut() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async () => {
      try {
        await api.del(apiV1AuthSessions.destroy())
      } finally {
        clearTokens()
        await qc.cancelQueries()
        qc.removeQueries()
      }
    },
  })
}
export function googleStartUrl(returnTo?: string, client: "web" | "native" = "web") {
  return apiV1AuthGoogleStart.show({ query: { client, returnTo: safeReturnPath(returnTo) ?? undefined } }).url
}
export async function captureGoogleCallback(qc: QueryClient, fragment = window.location.hash) {
  const values = new URLSearchParams(fragment.replace(/^#/, ""))
  // Erase the fragment before making any request or rendering another page.
  window.history.replaceState(null, "", window.location.pathname + window.location.search)
  const error = values.get("error")
  if (error) throw new Error(error)
  const token = values.get("token")
  if (!token) throw new Error("oauth_failed")
  await qc.cancelQueries()
  setToken(token)
  qc.removeQueries()
  await qc.fetchQuery(bootstrapOptions())
  return safeReturnPath(values.get("returnTo")) ?? "/dashboard"
}
export function useGoogleCallback() {
  const qc = useQueryClient()
  return useMutation({ mutationFn: () => captureGoogleCallback(qc) })
}
export function useEmailConfirmation(token: string) {
  return useQuery({
    queryKey: qk.emailConfirmation(token),
    queryFn: async ({ signal }) =>
      (await api.get<EmailChange>(apiV1SettingsEmailConfirmations.show(token), { signal })).data,
    enabled: Boolean(token),
    retry: false,
  })
}
export function useApplyEmailConfirmation() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (token: string) =>
      (await api.post<User>(apiV1SettingsEmailConfirmations.create(), { token })).data,
    onSuccess: async (_, token) => {
      qc.removeQueries({ queryKey: qk.emailConfirmation(token) })
      await Promise.all([
        qc.invalidateQueries({ queryKey: qk.bootstrap }),
        qc.invalidateQueries({ queryKey: ["invitation"] }),
      ])
    },
  })
}
export function useSwitchOrganization() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (organizationId: string) =>
      (await api.put<Auth>(apiV1CurrentOrganization.update(), { organizationId })).data,
    onSuccess: () => refreshOrganization(qc),
  })
}
export function useStopImpersonation() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async () => {
      await api.del(apiV1AuthImpersonation.destroy())
      const admin = localStorage.getItem(ADMIN_TOKEN_KEY)
      clearTokens()
      if (admin) setToken(admin)
      await qc.cancelQueries()
      qc.removeQueries()
      await qc.fetchQuery(bootstrapOptions())
    },
  })
}
