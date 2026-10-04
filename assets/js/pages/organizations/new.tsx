import { Head, useForm } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { FormField } from "@/components/app/form-field"
import { PageHeader } from "@/components/app/page-header"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { routes } from "@/generated/routes"

export default function OrganizationNew() {
  const { t } = useTranslation()
  const form = useForm({ name: "" })
  form.transform((data) => ({ organization: data }))

  return (
    <div className="max-w-xl">
      <Head title={t("organizations.new.title")} />
      <PageHeader title={t("organizations.new.title")} description={t("organizations.new.lead")} />
      <form
        className="grid gap-5"
        onSubmit={(event) => {
          event.preventDefault()
          form.post(routes.organization.create().url)
        }}
      >
        <FormField label={t("fields.organization_name")} help={t("organizations.new.name_help")} error={form.errors.name}>
          {(id, describedBy) => <Input id={id} aria-describedby={describedBy} required value={form.data.name} onChange={(e) => form.setData("name", e.target.value)} />}
        </FormField>
        <div>
          <Button type="submit" disabled={form.processing}>
            {t("organizations.new.submit")}
          </Button>
        </div>
      </form>
    </div>
  )
}
