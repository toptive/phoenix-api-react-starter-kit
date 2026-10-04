import { MailIcon, UsersIcon } from "lucide-react"
import { useNavigate } from "@tanstack/react-router"
import { useTranslation } from "react-i18next"
import { useForm, useWatch } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { toast } from "sonner"
import { useAppConfig } from "@/api/hooks/bootstrap"
import {
  isManager,
  useMembers,
  usePendingInvitations,
  useUpdateMembership,
  useRemoveMembership,
  useRevokeInvitation,
} from "@/api/hooks/people"
import type { Membership } from "@/api/generated/serializers"
import { membershipSchema } from "@/schemas/organizations"
import { applyFormErrors, fieldMessage } from "@/lib/form-errors"
import { SettingsSection } from "@/components/app/settings-section"
import { QueryState } from "@/components/app/query-state"
import { FormField } from "@/components/app/form-field"
import { FormError } from "@/components/app/form-error"
import { ConfirmDialog } from "@/components/app/confirm-dialog"
import { EmptyState } from "@/components/app/empty-state"
import { StatusBadge } from "@/components/app/status-badge"
import { InviteDialog } from "@/components/app/invite-dialog"
import { FieldHelp } from "@/components/app/field-help"
import { NativeSelect, NativeSelectOption } from "@/components/ui/native-select"
import { Button } from "@/components/ui/button"
import { formatDate } from "@/lib/format"
import { paths } from "@/lib/paths"

export default function MembersIndex() {
  const { t, i18n } = useTranslation()
  const { auth, app } = useAppConfig()
  const members = useMembers()
  const invitations = usePendingInvitations()
  const revoke = useRevokeInvitation()
  const canManage = isManager(auth!.membership)
  return (
    <SettingsSection title={t("settings.members.title")} description={t("settings.members.lead")}>
      <title>{t("settings.members.title")}</title>
      {canManage && (
        <div className="mb-6">
          <InviteDialog />
          {!app.emailAvailable && (
            <p className="mt-3 text-sm text-muted-foreground">{t("errors.api.email_unavailable")}</p>
          )}
        </div>
      )}
      {!canManage && <FieldHelp className="mb-6">{t("settings.members.read_only_help")}</FieldHelp>}
      <QueryState pending={members.isPending} error={members.error} retry={members.refetch} />
      {members.data?.length === 0 && (
        <EmptyState
          icon={UsersIcon}
          title={t("settings.members.empty_title")}
          description={t(canManage ? "settings.members.empty_help" : "settings.members.read_only_help")}
          action={
            canManage ? (
              <InviteDialog />
            ) : (
              <Button
                variant="outline"
                onClick={() => {
                  void members.refetch()
                }}
              >
                {t("common.retry")}
              </Button>
            )
          }
        />
      )}
      {Boolean(members.data?.length) && (
        <ul className="divide-y rounded-xl border bg-card">
          {members.data!.map((membership) => (
            <MemberRow key={membership.id} membership={membership} canManage={canManage} />
          ))}
        </ul>
      )}
      {canManage && (
        <section className="mt-10 space-y-3">
          <h2 className="font-semibold">{t("settings.members.pending_title")}</h2>
          <FieldHelp>{t("settings.members.pending_help")}</FieldHelp>
          <QueryState pending={invitations.isPending} error={invitations.error} retry={invitations.refetch} />
          <FormError error={revoke.error} />
          {invitations.data?.length === 0 && (
            <EmptyState
              icon={MailIcon}
              title={t("settings.members.pending_empty_title")}
              description={t("settings.members.pending_empty_help")}
              action={<InviteDialog />}
            />
          )}
          {Boolean(invitations.data?.length) && (
            <ul className="divide-y rounded-xl border bg-card">
              {invitations.data!.map((invitation) => (
                <li key={invitation.id} className="flex flex-wrap items-center gap-3 p-4">
                  <MailIcon className="size-4 shrink-0 text-muted-foreground" aria-hidden="true" />
                  <div className="min-w-0 flex-1">
                    <p className="font-medium break-all">{invitation.email}</p>
                    <p className="text-sm text-muted-foreground">
                      {t(`level.${invitation.role}_${invitation.access}`)} ·{" "}
                      {t("settings.members.expires", { date: formatDate(invitation.expiresAt, i18n.language) })}
                    </p>
                  </div>
                  <ConfirmDialog
                    trigger={
                      <Button variant="ghost" size="sm" disabled={revoke.isPending}>
                        {t("settings.members.revoke")}
                      </Button>
                    }
                    title={t("settings.members.revoke_title", { email: invitation.email })}
                    description={t("settings.members.revoke_body")}
                    confirmLabel={t("settings.members.revoke")}
                    onConfirm={() => revoke.mutate(invitation.id)}
                  />
                </li>
              ))}
            </ul>
          )}
        </section>
      )}
    </SettingsSection>
  )
}
function MemberRow({ membership, canManage }: { membership: Membership; canManage: boolean }) {
  const { t } = useTranslation()
  const { auth } = useAppConfig()
  const navigate = useNavigate()
  const remove = useRemoveMembership()
  const isMe = membership.id === auth!.membership.id
  const owner = auth!.membership.role === "owner"
  const canChange = canManage && (membership.role !== "owner" || owner)
  const user = membership.user
  const name = user?.name || user?.email || t("settings.members.unknown_person")
  return (
    <li className="space-y-4 p-4">
      <div className="flex flex-wrap items-center gap-4">
        <div className="min-w-0 flex-1">
          <p className="font-medium break-words">
            {name} {isMe && <span className="text-muted-foreground">({t("settings.members.you")})</span>}
          </p>
          <p className="text-sm break-all text-muted-foreground">{user?.email}</p>
        </div>
        <StatusBadge tone={membership.role === "owner" ? "info" : "neutral"}>
          {t(`level.${membership.role}_${membership.access}`)}
        </StatusBadge>
        {(isMe || canChange) && (
          <ConfirmDialog
            trigger={
              <Button variant="ghost" size="sm" disabled={remove.isPending}>
                {t(isMe ? "settings.members.leave" : "settings.members.remove")}
              </Button>
            }
            title={t(isMe ? "settings.members.leave_title" : "settings.members.remove_title", { name })}
            description={t(isMe ? "settings.members.leave_body" : "settings.members.remove_body")}
            confirmLabel={t(isMe ? "settings.members.leave" : "settings.members.remove")}
            onConfirm={() =>
              remove.mutate(membership.id, {
                onSuccess: () => {
                  if (isMe) void navigate({ to: paths.dashboard })
                  else toast.success(t("settings.members.removed"))
                },
              })
            }
          />
        )}
      </div>
      {canChange && <MembershipForm membership={membership} owner={owner} name={name} />}
      <FormError error={remove.error} />
    </li>
  )
}
function MembershipForm({ membership, owner, name }: { membership: Membership; owner: boolean; name: string }) {
  const { t } = useTranslation()
  const update = useUpdateMembership()
  const form = useForm({
    resolver: zodResolver(membershipSchema),
    defaultValues: { role: membership.role, access: membership.access },
  })
  const access = useWatch({ control: form.control, name: "access" })
  return (
    <form
      noValidate
      className="grid gap-3 sm:grid-cols-[1fr_1fr_auto] sm:items-end"
      onSubmit={form.handleSubmit(async (input) => {
        try {
          await update.mutateAsync({ id: membership.id, ...input })
          form.reset(input)
          toast.success(t("common.saved"))
        } catch (error) {
          applyFormErrors(error, form.setError)
        }
      })}
    >
      <FormField
        label={t("settings.members.role_for", { name })}
        error={fieldMessage(form.formState.errors.role?.message)}
      >
        {(id, describedBy) => (
          <NativeSelect className="min-h-11" id={id} aria-describedby={describedBy} {...form.register("role")}>
            {(owner ? ["owner", "admin", "member"] : ["admin", "member"]).map((role) => (
              <NativeSelectOption key={role} value={role}>
                {t(access === "viewer" ? `role.${role}` : `level.${role}_full`)}
              </NativeSelectOption>
            ))}
          </NativeSelect>
        )}
      </FormField>
      <FormField label={t("settings.members.access_label")} error={fieldMessage(form.formState.errors.access?.message)}>
        {(id, describedBy) => (
          <NativeSelect className="min-h-11" id={id} aria-describedby={describedBy} {...form.register("access")}>
            {["full", "viewer"].map((access) => (
              <NativeSelectOption key={access} value={access}>
                {t(`settings.members.access.${access}`)}
              </NativeSelectOption>
            ))}
          </NativeSelect>
        )}
      </FormField>
      <Button type="submit" variant="outline" disabled={update.isPending || !form.formState.isDirty}>
        {t("common.save")}
      </Button>
      <div className="sm:col-span-3">
        <FormError message={form.formState.errors.root?.message} />
      </div>
    </form>
  )
}
