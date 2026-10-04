import { Head, useForm } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { AuthHeading } from "@/components/app/auth-card"
import { Button } from "@/components/ui/button"
import { routes } from "@/generated/routes"
import type { MagicLinksShowProps } from "@/generated/pages"


/** A button, not an automatic sign-in: email scanners that open links cannot use the token. */
export default function MagicLinkShow({ token, email, confirmed }: MagicLinksShowProps) {
  const { t } = useTranslation()
  const form = useForm({ token, rememberMe: true })
  form.transform((data) => ({ user: data }))

  return (
    <>
      <Head title={t("auth.magic_link.title")} />
      <AuthHeading
        title={confirmed ? t("auth.magic_link.title") : t("auth.magic_link.confirm_title")}
        description={t("auth.magic_link.lead", { email })}
      />
      <form
        onSubmit={(event) => {
          event.preventDefault()
          form.post(routes.session.create().url)
        }}
      >
        <Button type="submit" size="lg" className="w-full" disabled={form.processing}>
          {confirmed ? t("auth.magic_link.submit") : t("auth.magic_link.confirm_submit")}
        </Button>
      </form>
    </>
  )
}
