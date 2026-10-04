import { Head, router, useForm } from "@inertiajs/react"
import { MailIcon, UserPlusIcon } from "lucide-react"
import { useState } from "react"
import { useTranslation } from "react-i18next"

import { ConfirmDialog } from "@/components/app/confirm-dialog"
import { FieldHelp } from "@/components/app/field-help"
import { FormField } from "@/components/app/form-field"
import { FormStepper } from "@/components/app/form-stepper"
import { SettingsSection } from "@/components/app/settings-section"
import { StatusBadge } from "@/components/app/status-badge"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { NativeSelect, NativeSelectOption } from "@/components/ui/native-select"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { formatDate } from "@/lib/format"
import { routes } from "@/generated/routes"
import type { Membership } from "@/generated/serializers"
import type { SettingsMembersIndexProps } from "@/generated/pages"

type Role = Membership["role"]
type Access = Membership["access"]


/** "Who is in my organization, and who did I invite?" — one screen for both. */
export default function MembersIndex({ memberships, invitations, canManage, auth, locale }: SettingsMembersIndexProps) {
  const { t } = useTranslation()
  const me = auth?.user.id
  const iAmOwner = auth?.membership.role === "owner"
  const options: [Role, Access][] = iAmOwner ? [["owner", "full"], ...roleOptions] : roleOptions

  return (
    <SettingsSection title={t("settings.members.title")} description={t("settings.members.lead")}>
      <Head title={t("settings.members.title")} />

      {canManage && (
        <div className="mb-6">
          <InviteDialog />
        </div>
      )}

      <ul className="divide-y rounded-xl border bg-card">
        {memberships.map((membership) => {
          const user = membership.user
          const isMe = user?.id === me
          return (
            <li key={membership.id} className="flex flex-wrap items-center gap-4 p-4">
              <div className="min-w-0 flex-1">
                <p className="truncate font-medium">
                  {user?.name || user?.email} {isMe && <span className="text-muted-foreground">({t("settings.members.you")})</span>}
                </p>
                <p className="truncate text-sm text-muted-foreground">{user?.email}</p>
              </div>
              {canManage && !isMe && (membership.role !== "owner" || iAmOwner) ? (
                <NativeSelect
                  aria-label={t("settings.members.role_for", { name: user?.name || user?.email })}
                  value={`${membership.role}:${membership.access}`}
                  onChange={(e) => {
                    const [role, access] = e.target.value.split(":")
                    router.patch(routes.settingsMembership.update(membership.id).url, { membership: { role, access } }, { preserveScroll: true })
                  }}
                >
                  {options.map(([role, access]) => (
                    <NativeSelectOption key={`${role}:${access}`} value={`${role}:${access}`}>
                      {t(`level.${role}_${access}`)}
                    </NativeSelectOption>
                  ))}
                </NativeSelect>
              ) : (
                <StatusBadge tone={membership.role === "owner" ? "info" : "neutral"}>{t(`level.${membership.role}_${membership.access}`)}</StatusBadge>
              )}
              {(isMe || canManage) && (
                <ConfirmDialog
                  trigger={<Button variant="ghost" size="sm">{isMe ? t("settings.members.leave") : t("settings.members.remove")}</Button>}
                  title={isMe ? t("settings.members.leave_title") : t("settings.members.remove_title", { name: user?.name || user?.email })}
                  description={isMe ? t("settings.members.leave_body") : t("settings.members.remove_body")}
                  confirmLabel={isMe ? t("settings.members.leave") : t("settings.members.remove")}
                  onConfirm={() => router.delete(routes.settingsMembership.delete(membership.id).url)}
                />
              )}
            </li>
          )
        })}
      </ul>

      {canManage && invitations.length > 0 && (
        <section aria-labelledby="pending" className="mt-10">
          <h2 id="pending" className="text-lg font-semibold">{t("settings.members.pending_title")}</h2>
          <FieldHelp className="mt-1">{t("settings.members.pending_help")}</FieldHelp>
          <ul className="mt-4 divide-y rounded-xl border bg-card">
            {invitations.map((invitation) => (
              <li key={invitation.id} className="flex flex-wrap items-center gap-4 p-4">
                <MailIcon className="size-5 text-muted-foreground" aria-hidden="true" />
                <div className="min-w-0 flex-1">
                  <p className="truncate font-medium">{invitation.email}</p>
                  <p className="text-sm text-muted-foreground">
                    {t(`level.${invitation.role}_${invitation.access}`)} · {t("settings.members.expires", { date: formatDate(invitation.expiresAt, locale) })}
                  </p>
                </div>
                <ConfirmDialog
                  trigger={<Button variant="ghost" size="sm">{t("settings.members.revoke")}</Button>}
                  title={t("settings.members.revoke_title", { email: invitation.email })}
                  description={t("settings.members.revoke_body")}
                  confirmLabel={t("settings.members.revoke")}
                  onConfirm={() => router.delete(routes.settingsInvitation.delete(invitation.id).url, { preserveScroll: true })}
                />
              </li>
            ))}
          </ul>
        </section>
      )}
    </SettingsSection>
  )
}

const roleOptions: [Role, Access][] = [
  ["admin", "full"],
  ["member", "full"],
  ["member", "viewer"],
]

/** Inviting is a small task in three steps: who, what they can do, check and send. */
function InviteDialog() {
  const { t } = useTranslation()
  const [open, setOpen] = useState(false)
  const form = useForm({ email: "", role: "member" as Role, access: "full" as Access })
  form.transform((data) => ({ invitation: data }))

  const choice = `${form.data.role}:${form.data.access}`

  return (
    <Dialog open={open} onOpenChange={(next) => { setOpen(next); if (!next) form.reset() }}>
      <DialogTrigger asChild>
        <Button>
          <UserPlusIcon aria-hidden="true" /> {t("settings.members.invite")}
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("settings.members.invite")}</DialogTitle>
          <DialogDescription>{t("settings.members.invite_lead")}</DialogDescription>
        </DialogHeader>
        <FormStepper
          processing={form.processing}
          submitLabel={t("settings.members.send_invite")}
          onSubmit={() => form.post(routes.settingsInvitation.create().url, { preserveScroll: true, onSuccess: () => { setOpen(false); form.reset() } })}
          steps={[
            {
              title: t("settings.members.step_email"),
              isValid: () => /\S+@\S+/.test(form.data.email),
              content: (
                <FormField label={t("fields.email")} help={t("settings.members.email_help")} error={form.errors.email}>
                  {(id, describedBy) => <Input id={id} type="email" autoFocus aria-describedby={describedBy} value={form.data.email} onChange={(e) => form.setData("email", e.target.value)} />}
                </FormField>
              ),
            },
            {
              title: t("settings.members.step_role"),
              content: (
                <RadioGroup
                  value={choice}
                  onValueChange={(value) => {
                    const [role, access] = value.split(":") as [Role, Access]
                    form.setData((data) => ({ ...data, role, access }))
                  }}
                  className="gap-3"
                >
                  {roleOptions.map(([role, access]) => {
                    const value = `${role}:${access}`
                    return (
                      <Label key={value} htmlFor={value} className="flex cursor-pointer items-start gap-3 rounded-lg border p-3 font-normal has-[[data-state=checked]]:border-primary">
                        <RadioGroupItem id={value} value={value} className="mt-0.5" />
                        <span>
                          <span className="block font-medium">{t(`level.${role}_${access}`)}</span>
                          <span className="block text-sm text-muted-foreground">{t(`settings.members.explain.${role}_${access}`)}</span>
                        </span>
                      </Label>
                    )
                  })}
                </RadioGroup>
              ),
            },
            {
              title: t("settings.members.step_review"),
              content: (
                <dl className="grid gap-3 rounded-lg bg-muted p-4 text-sm">
                  <div>
                    <dt className="text-muted-foreground">{t("fields.email")}</dt>
                    <dd className="font-medium">{form.data.email}</dd>
                  </div>
                  <div>
                    <dt className="text-muted-foreground">{t("settings.members.can")}</dt>
                    <dd className="font-medium">{t(`settings.members.explain.${form.data.role}_${form.data.access}`)}</dd>
                  </div>
                  {form.errors.email && <p className="text-destructive" role="alert">{form.errors.email}</p>}
                </dl>
              ),
            },
          ]}
        />
      </DialogContent>
    </Dialog>
  )
}
