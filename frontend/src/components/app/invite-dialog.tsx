import { limits } from "@/schemas/limits"
import { useState } from "react"
import { useForm, useWatch } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { useTranslation } from "react-i18next"
import { UserPlusIcon } from "lucide-react"
import { toast } from "sonner"
import { useInvitePerson } from "@/api/hooks/people"
import { useAppConfig } from "@/api/hooks/bootstrap"
import { invitationSchema, type InvitationInput } from "@/schemas/organizations"
import { emailSchema } from "@/schemas/auth"
import { applyFormErrors, fieldMessage } from "@/lib/form-errors"
import { FormField } from "./form-field"
import { FormStepper } from "./form-stepper"
import { FormError } from "./form-error"
import { FieldHelp } from "./field-help"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogTrigger,
} from "@/components/ui/dialog"
import { NativeSelect, NativeSelectOption } from "@/components/ui/native-select"

export function InviteDialog() {
  const { t } = useTranslation()
  const { app } = useAppConfig()
  const [open, setOpen] = useState(false)
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button disabled={!app.emailAvailable}>
          <UserPlusIcon aria-hidden="true" />
          {t("settings.members.invite")}
        </Button>
      </DialogTrigger>
      <DialogContent className="max-h-[90dvh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{t("settings.members.invite")}</DialogTitle>
          <DialogDescription>{t("settings.members.invite_lead")}</DialogDescription>
        </DialogHeader>
        {open && <InviteForm onSent={() => setOpen(false)} />}
      </DialogContent>
    </Dialog>
  )
}
function InviteForm({ onSent }: { onSent: () => void }) {
  const { t } = useTranslation()
  const invite = useInvitePerson()
  const form = useForm<InvitationInput>({
    resolver: zodResolver(invitationSchema),
    defaultValues: { email: "", role: "member", access: "full" },
  })
  const values = useWatch({ control: form.control })
  const [step, setStep] = useState(0)
  return (
    <FormStepper
      processing={invite.isPending}
      stepIndex={step}
      onStepChange={setStep}
      reviewLastStep
      submitLabel={t("settings.members.send_invite")}
      onSubmit={() => {
        void form.handleSubmit(
          async (input) => {
            try {
              await invite.mutateAsync(input)
              toast.success(t("settings.members.invite_sent"))
              onSent()
            } catch (error) {
              applyFormErrors(error, form.setError)
              setStep(0)
            }
          },
          () => setStep(0),
        )()
      }}
      steps={[
        {
          title: t("settings.members.step_email"),
          isValid: () => emailSchema.safeParse(form.getValues("email")).success,
          content: (
            <>
              <FormField
                label={t("fields.email")}
                help={t("settings.members.email_help")}
                error={fieldMessage(form.formState.errors.email?.message, { count: limits.emailMax })}
              >
                {(id, describedBy) => (
                  <Input
                    id={id}
                    type="email"
                    autoComplete="email"
                    aria-describedby={describedBy}
                    {...form.register("email")}
                  />
                )}
              </FormField>
              <FormError message={form.formState.errors.root?.message} />
            </>
          ),
        },
        {
          title: t("settings.members.step_role"),
          content: (
            <>
              <FormField
                label={t("settings.members.role_label")}
                error={fieldMessage(form.formState.errors.role?.message)}
              >
                {(id, describedBy) => (
                  <NativeSelect className="min-h-11" id={id} aria-describedby={describedBy} {...form.register("role")}>
                    {(["admin", "member"] as const).map((role) => (
                      <NativeSelectOption key={role} value={role}>
                        {t(values.access === "viewer" ? `role.${role}` : `level.${role}_full`)}
                      </NativeSelectOption>
                    ))}
                  </NativeSelect>
                )}
              </FormField>
              <FormField
                label={t("settings.members.access_label")}
                error={fieldMessage(form.formState.errors.access?.message)}
              >
                {(id, describedBy) => (
                  <NativeSelect
                    className="min-h-11"
                    id={id}
                    aria-describedby={describedBy}
                    {...form.register("access")}
                  >
                    {(["full", "viewer"] as const).map((access) => (
                      <NativeSelectOption key={access} value={access}>
                        {t(`settings.members.access.${access}`)}
                      </NativeSelectOption>
                    ))}
                  </NativeSelect>
                )}
              </FormField>
              <FieldHelp>{t(`settings.members.explain.${values.role}_${values.access}`)}</FieldHelp>
            </>
          ),
        },
        {
          title: t("settings.members.step_review"),
          content: (
            <dl className="grid gap-3 rounded-lg bg-muted p-4 text-sm">
              <div>
                <dt className="text-muted-foreground">{t("fields.email")}</dt>
                <dd className="font-medium break-all">{values.email}</dd>
              </div>
              <div>
                <dt className="text-muted-foreground">{t("settings.members.can")}</dt>
                <dd className="font-medium">{t(`settings.members.explain.${values.role}_${values.access}`)}</dd>
              </div>
            </dl>
          ),
        },
      ]}
    />
  )
}
