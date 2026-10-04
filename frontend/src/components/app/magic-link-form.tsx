import { limits } from "@/schemas/limits"
import { useCallback, useState } from "react"
import { useForm, useWatch } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { useNavigate } from "@tanstack/react-router"
import { useTranslation } from "react-i18next"
import { useRequestMagicLink } from "@/api/hooks/auth"
import { useAppConfig } from "@/api/hooks/bootstrap"
import { FormField } from "./form-field"
import { FormError } from "./form-error"
import { Turnstile } from "./turnstile"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { magicLinkSchema } from "@/schemas/auth"
import { applyFormErrors, fieldMessage } from "@/lib/form-errors"
import { paths } from "@/lib/paths"
/** Sign-in and sudo request the same scanner-safe magic link. */
export function MagicLinkForm({ email = "", onSent }: { email?: string; onSent?: () => void }) {
  const { t } = useTranslation()
  const { turnstile } = useAppConfig()
  const navigate = useNavigate()
  const form = useForm({ resolver: zodResolver(magicLinkSchema), defaultValues: { email, turnstileToken: "" } })
  const request = useRequestMagicLink()
  const [attempt, setAttempt] = useState(0)
  const { setValue } = form
  const onToken = useCallback((token: string) => setValue("turnstileToken", token), [setValue])
  const token = useWatch({ control: form.control, name: "turnstileToken" })
  return (
    <form
      noValidate
      className="grid gap-5"
      onSubmit={form.handleSubmit(async (input) => {
        try {
          const result = await request.mutateAsync(input)
          if (onSent) onSent()
          else void navigate({ to: paths.checkEmail, search: { email: result.email } })
        } catch (error) {
          applyFormErrors(error, form.setError)
        } finally {
          setAttempt((value) => value + 1)
          setValue("turnstileToken", "")
        }
      })}
    >
      <FormField
        label={t("fields.email")}
        help={t("auth.session.link_help")}
        error={fieldMessage(form.formState.errors.email?.message, { count: limits.emailMax })}
      >
        {(id, describedBy) => (
          <Input id={id} aria-describedby={describedBy} type="email" autoComplete="email" {...form.register("email")} />
        )}
      </FormField>
      <Turnstile
        action="magic_link"
        attempt={attempt}
        onToken={onToken}
        error={fieldMessage(form.formState.errors.turnstileToken?.message)}
      />
      <FormError message={form.formState.errors.root?.message} />
      <Button type="submit" size="lg" disabled={request.isPending || (turnstile.required && !token)}>
        {t("auth.session.send_link")}
      </Button>
    </form>
  )
}
