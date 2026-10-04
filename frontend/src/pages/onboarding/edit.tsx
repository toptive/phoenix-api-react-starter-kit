import { useState } from "react"
import { Navigate, useNavigate } from "@tanstack/react-router"
import { useForm, useWatch } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { useTranslation } from "react-i18next"
import { useOnboarding, useCompleteOnboarding } from "@/api/hooks/organizations"
import { PageHeader } from "@/components/app/page-header"
import { FormField } from "@/components/app/form-field"
import { FormStepper } from "@/components/app/form-stepper"
import { FormError } from "@/components/app/form-error"
import { QueryState } from "@/components/app/query-state"
import { Input } from "@/components/ui/input"
import { onboardingSchema } from "@/schemas/organizations"
import { limits } from "@/schemas/limits"
import { applyFormErrors, boundedFieldMessage } from "@/lib/form-errors"
import { paths } from "@/lib/paths"

export default function OnboardingEdit() {
  const { t } = useTranslation()
  const query = useOnboarding()
  if (query.data && !query.data.required) return <Navigate to={paths.dashboard} replace />
  return (
    <div className="max-w-xl">
      <title>{t("onboarding.title")}</title>
      <PageHeader title={t("onboarding.title")} description={t("onboarding.lead")} />
      <QueryState pending={query.isPending} error={query.error} retry={query.refetch} />
      {query.data && <OnboardingForm organizationName={query.data.organizationName} />}
    </div>
  )
}
function OnboardingForm({ organizationName }: { organizationName: string }) {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const form = useForm({ resolver: zodResolver(onboardingSchema), defaultValues: { name: "" } })
  const name = useWatch({ control: form.control, name: "name" })
  const complete = useCompleteOnboarding()
  const [step, setStep] = useState(0)
  const nameIssue = onboardingSchema.safeParse({ name }).error?.issues[0]?.message
  const error = boundedFieldMessage(form.formState.errors.name?.message, limits.organizationMin, limits.organizationMax)
  return (
    <FormStepper
      processing={complete.isPending}
      stepIndex={step}
      onStepChange={setStep}
      reviewLastStep
      submitLabel={t("onboarding.submit")}
      onSubmit={() => {
        void form.handleSubmit(
          async (input) => {
            try {
              await complete.mutateAsync(input)
              void navigate({ to: paths.dashboard })
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
          title: t("onboarding.name.title"),
          description: t("onboarding.name.description"),
          isValid: () => onboardingSchema.safeParse(form.getValues()).success,
          validationMessage:
            boundedFieldMessage(nameIssue, limits.organizationMin, limits.organizationMax) ??
            t("onboarding.name.too_short"),
          skipLabel: t("onboarding.skip"),
          onSkip: () => {
            form.setValue("name", "")
            form.clearErrors()
          },
          content: (
            <>
              <FormField label={t("fields.organization_name")} help={t("onboarding.name.help")} error={error}>
                {(id, describedBy) => (
                  <Input
                    id={id}
                    aria-describedby={describedBy}
                    autoComplete="organization"
                    placeholder={organizationName}
                    {...form.register("name")}
                  />
                )}
              </FormField>
              <FormError message={form.formState.errors.root?.message} />
            </>
          ),
        },
        {
          title: t("stepper.review"),
          content: (
            <dl className="grid gap-1 rounded-xl border border-border p-4">
              <dt className="text-sm text-muted-foreground">{t("fields.organization_name")}</dt>
              <dd className="font-medium">{name.trim() || organizationName}</dd>
            </dl>
          ),
        },
      ]}
    />
  )
}
