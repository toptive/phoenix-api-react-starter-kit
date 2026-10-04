import { useCallback, useEffect, useRef, useState, type ReactNode } from "react"
import { useRouter } from "@tanstack/react-router"
import { i18n } from "@/i18n"
import { useTranslation } from "react-i18next"
import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { useSudo } from "@/api/hooks/auth"
import { useAppConfig } from "@/api/hooks/bootstrap"
import { ApiError } from "@/api/http"
import { SudoContext } from "@/hooks/use-sudo-action"
import { magicLinkToken } from "@/lib/sudo"
import { applyFormErrors, fieldMessage } from "@/lib/form-errors"
import { sudoSchema, sudoLinkSchema } from "@/schemas/auth"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { FormField } from "./form-field"
import { FormError } from "./form-error"
import { MagicLinkForm } from "./magic-link-form"

export function SudoProvider({ children }: { children: ReactNode }) {
  const { t } = useTranslation()
  const router = useRouter()
  const [open, setOpen] = useState(false)
  const waiting = useRef<{ resolve: () => void; reject: (reason: Error) => void }[]>([])
  const confirm = useCallback(
    () =>
      new Promise<void>((resolve, reject) => {
        waiting.current.push({ resolve, reject })
        setOpen(true)
      }),
    [],
  )
  const cancel = useCallback(() => {
    waiting.current
      .splice(0)
      .forEach(({ reject }) =>
        reject(new ApiError({ code: "sudo_cancelled", message: i18n.t("auth.sudo.cancelled"), details: {} }, 0)),
      )
    setOpen(false)
  }, [])
  useEffect(
    () => () => {
      waiting.current
        .splice(0)
        .forEach(({ reject }) =>
          reject(new ApiError({ code: "sudo_cancelled", message: i18n.t("auth.sudo.cancelled"), details: {} }, 0)),
        )
    },
    [],
  )
  useEffect(() => router.subscribe("onBeforeNavigate", cancel), [router, cancel])
  return (
    <SudoContext.Provider value={confirm}>
      {children}
      <Dialog
        open={open}
        onOpenChange={(next) => {
          if (!next) cancel()
        }}
      >
        <DialogContent className="max-h-[90dvh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{t("auth.sudo.title")}</DialogTitle>
            <DialogDescription>{t("auth.sudo.dialog_lead")}</DialogDescription>
          </DialogHeader>
          {open && (
            <SudoForm
              onConfirmed={() => {
                waiting.current.splice(0).forEach(({ resolve }) => resolve())
                setOpen(false)
              }}
            />
          )}
        </DialogContent>
      </Dialog>
    </SudoContext.Provider>
  )
}
function SudoForm({ onConfirmed }: { onConfirmed: () => void }) {
  const { t } = useTranslation()
  const { auth, app } = useAppConfig()
  const sudo = useSudo()
  const password = useForm({ resolver: zodResolver(sudoSchema), defaultValues: { password: "" } })
  const link = useForm({ resolver: zodResolver(sudoLinkSchema), defaultValues: { link: "" } })
  const [sent, setSent] = useState(false)
  if (auth?.impersonator) return <FormError message={t("errors.api.forbidden")} />
  return (
    <div className="grid gap-6">
      {auth?.user.hasPassword && (
        <form
          noValidate
          className="grid gap-4"
          onSubmit={password.handleSubmit(async (input) => {
            try {
              await sudo.mutateAsync(input)
              onConfirmed()
            } catch (error) {
              password.setValue("password", "")
              applyFormErrors(error, password.setError)
            }
          })}
        >
          <FormField label={t("fields.password")} error={fieldMessage(password.formState.errors.password?.message)}>
            {(id, describedBy) => (
              <Input
                id={id}
                aria-describedby={describedBy}
                type="password"
                autoComplete="current-password"
                {...password.register("password")}
              />
            )}
          </FormField>
          <FormError message={password.formState.errors.root?.message} />
          <Button disabled={sudo.isPending} type="submit">
            {t("auth.sudo.confirm")}
          </Button>
        </form>
      )}
      {app.emailAvailable ? (
        <>
          <details open={!auth?.user.hasPassword} className="space-y-4">
            <summary className="min-h-11 cursor-pointer py-3 text-sm font-medium">{t("auth.sudo.use_link")}</summary>
            {!sent ? (
              <MagicLinkForm email={auth?.user.email} onSent={() => setSent(true)} />
            ) : (
              <p role="status" className="text-sm text-muted-foreground">
                {t("auth.sudo.link_sent")}
              </p>
            )}
            <form
              noValidate
              className="grid gap-4"
              onSubmit={link.handleSubmit(async ({ link: value }) => {
                try {
                  await sudo.mutateAsync({ magicLinkToken: magicLinkToken(value)! })
                  onConfirmed()
                } catch (error) {
                  applyFormErrors(error, link.setError)
                }
              })}
            >
              <FormField
                label={t("auth.sudo.link_label")}
                help={t("auth.sudo.link_help")}
                error={fieldMessage(link.formState.errors.link?.message)}
              >
                {(id, describedBy) => (
                  <Input id={id} aria-describedby={describedBy} autoComplete="off" {...link.register("link")} />
                )}
              </FormField>
              <FormError message={link.formState.errors.root?.message} />
              <Button disabled={sudo.isPending} type="submit">
                {t("auth.sudo.confirm")}
              </Button>
            </form>
          </details>
        </>
      ) : (
        <p className="text-sm text-muted-foreground">{t("auth.unavailable.session_body")}</p>
      )}
    </div>
  )
}
