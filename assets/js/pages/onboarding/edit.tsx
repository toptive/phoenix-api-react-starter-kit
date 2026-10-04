import { Head, useForm } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { FormField } from "@/components/app/form-field"
import { FormStepper } from "@/components/app/form-stepper"
import { PageHeader } from "@/components/app/page-header"
import { Input } from "@/components/ui/input"
import type { OnboardingEditProps } from "@/generated/pages"
import { routes } from "@/generated/routes"

/**
 * First-run steps for a new organization. Every step is optional ("Skip for now"); the
 * last one reviews the answers and finishes. A product replaces the steps with its own
 * questions (and `Organizations.complete_onboarding/2` with what it saves).
 */
export default function OnboardingEdit({ organizationName }: OnboardingEditProps) {
  const { t } = useTranslation()
  const form = useForm({ name: "" })
  form.transform((data) => ({ onboarding: data }))

  return (
    <div className="max-w-xl">
      <Head title={t("onboarding.title")} />
      <PageHeader title={t("onboarding.title")} description={t("onboarding.lead")} />
      <FormStepper
        processing={form.processing}
        submitLabel={t("onboarding.submit")}
        onSubmit={() => form.patch(routes.onboarding.update().url)}
        reviewLastStep
        steps={[
          {
            title: t("onboarding.name.title"),
            description: t("onboarding.name.description"),
            isValid: () => form.data.name.trim().length !== 1,
            validationMessage: t("onboarding.name.too_short"),
            skipLabel: t("onboarding.skip"),
            onSkip: () => form.setData("name", ""),
            content: (
              <FormField label={t("fields.organization_name")} help={t("onboarding.name.help")} error={form.errors.name}>
                {(id, describedBy) => (
                  <Input
                    id={id}
                    aria-describedby={describedBy}
                    autoComplete="organization"
                    placeholder={organizationName}
                    value={form.data.name}
                    onChange={(e) => form.setData("name", e.target.value)}
                  />
                )}
              </FormField>
            ),
          },
          {
            title: t("stepper.review"),
            content: (
              <dl className="grid gap-1 rounded-xl border border-border p-4">
                <dt className="text-sm text-muted-foreground">{t("fields.organization_name")}</dt>
                <dd className="font-medium">{form.data.name.trim() || organizationName}</dd>
                {form.errors.name && (
                  <dd role="alert" className="text-sm text-destructive">
                    {form.errors.name}
                  </dd>
                )}
              </dl>
            ),
          },
        ]}
      />
    </div>
  )
}
