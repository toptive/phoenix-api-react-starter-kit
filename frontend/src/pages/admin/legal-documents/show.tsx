import { useState } from "react"
import { useParams } from "@tanstack/react-router"
import { useForm, useWatch } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { useTranslation } from "react-i18next"
import { toast } from "sonner"
import { useLegalDocument, useCreateLegalVersion, usePublishLegalVersion } from "@/api/hooks/admin"
import { useAppConfig } from "@/api/hooks/bootstrap"
import type { LegalDocument } from "@/api/generated/serializers"
import { legalVersionSchema } from "@/schemas/admin"
import { applyFormErrors, fieldMessage } from "@/lib/form-errors"
import { formatDateTime } from "@/lib/format"
import { PageHeader } from "@/components/app/page-header"
import { QueryState } from "@/components/app/query-state"
import { ConfirmDialog } from "@/components/app/confirm-dialog"
import { FormField } from "@/components/app/form-field"
import { FormError } from "@/components/app/form-error"
import { FormStepper } from "@/components/app/form-stepper"
import { FieldHelp } from "@/components/app/field-help"
import { DataTable } from "@/components/app/data-table"
import { LegalBody } from "@/components/app/legal-body"
import { StatusBadge } from "@/components/app/status-badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"

export default function AdminLegalShow() {
  const { slug = "" } = useParams({ strict: false }) as { slug?: string }
  const { t, i18n } = useTranslation()
  const query = useLegalDocument(slug)
  const publish = usePublishLegalVersion(slug)
  if (!query.data) return <QueryState pending={query.isPending} error={query.error} retry={query.refetch} />
  const document = query.data
  return (
    <>
      <title>{t(`legal.${slug}`)}</title>
      <PageHeader title={t(`legal.${slug}`)} description={t("admin.legal.show_lead")} />
      <div className="grid gap-10 xl:grid-cols-[1.6fr_1fr]">
        <VersionForm key={document.id} document={document} />
        <section className="min-w-0 space-y-4">
          <h2 className="text-lg font-semibold">{t("admin.legal.versions")}</h2>
          <FieldHelp>{t("admin.legal.versions_help")}</FieldHelp>
          <DataTable
            rows={document.versions}
            rowKey={(version) => version.id}
            empty={<p>{t("admin.empty")}</p>}
            columns={[
              {
                header: t("admin.legal.versions"),
                cell: (version) => (
                  <details>
                    <summary className="min-h-11 cursor-pointer py-2 font-medium">
                      {t("admin.legal.version", { version: version.number })}
                    </summary>
                    <p className="text-sm text-muted-foreground">{formatDateTime(version.insertedAt, i18n.language)}</p>
                    {version.note && <p className="my-2 text-sm">{version.note}</p>}
                    {Object.keys(version.titles).map((locale) => (
                      <div key={locale} className="my-4 space-y-2">
                        <h3 className="font-semibold">
                          {t(`locale.name.${locale}`)}
                          {": "}
                          {version.titles[locale]}
                        </h3>
                        <LegalBody body={version.bodies[locale] ?? ""} />
                      </div>
                    ))}
                  </details>
                ),
              },
              {
                header: t("admin.legal.publication"),
                cell: (version) =>
                  version.id === document.publishedVersionId ? (
                    <StatusBadge tone="success">{t("admin.legal.live")}</StatusBadge>
                  ) : (
                    <ConfirmDialog
                      destructive={false}
                      trigger={
                        <Button variant="outline" disabled={publish.isPending}>
                          {t("admin.legal.publish")}
                        </Button>
                      }
                      title={t("admin.legal.publish_title", { version: version.number })}
                      description={t("admin.legal.publish_body")}
                      confirmLabel={t("admin.legal.publish")}
                      onConfirm={async () => {
                        await publish.mutateAsync(version.number)
                        toast.success(t("flash.legal.published"))
                      }}
                    />
                  ),
              },
            ]}
          />
          <FormError error={publish.error} />
        </section>
      </div>
    </>
  )
}
function VersionForm({ document }: { document: LegalDocument }) {
  const { t } = useTranslation()
  const { locales } = useAppConfig()
  const create = useCreateLegalVersion(document.slug)
  const [step, setStep] = useState(0)
  const latest = document.versions[0]
  const empty = Object.fromEntries(locales.map((locale) => [locale, ""]))
  const form = useForm({
    resolver: zodResolver(legalVersionSchema),
    defaultValues: {
      titles: { ...empty, ...latest?.titles },
      bodies: { ...empty, ...latest?.bodies },
      note: "",
      publish: false,
    },
  })
  const values = useWatch({ control: form.control })
  const submit = (publish: boolean) => {
    form.setValue("publish", publish)
    void form.handleSubmit(
      async (input) => {
        try {
          await create.mutateAsync(input)
          form.reset({ ...input, note: "", publish: false })
          toast.success(t(input.publish ? "flash.legal.published" : "common.saved"))
          setStep(0)
        } catch (error) {
          applyFormErrors(error, form.setError)
          setStep(0)
        }
      },
      () => setStep(0),
    )()
  }
  return (
    <section className="space-y-4">
      <h2 className="text-lg font-semibold">{t("admin.legal.new_version")}</h2>
      <FormStepper
        stepIndex={step}
        onStepChange={setStep}
        processing={create.isPending}
        reviewLastStep
        submitLabel={t("admin.legal.save")}
        onSubmit={() => submit(false)}
        steps={[
          ...locales.map((locale) => ({
            title: t(`locale.name.${locale}`),
            validationMessage: t("validation.english_required"),
            isValid: () =>
              locale !== "en" || Boolean(form.getValues("titles.en").trim() && form.getValues("bodies.en").trim()),
            content: (
              <div className="grid gap-4">
                <FormField
                  label={t("admin.legal.doc_title")}
                  error={fieldMessage(
                    typeof form.formState.errors.titles?.message === "string"
                      ? form.formState.errors.titles.message
                      : undefined,
                  )}
                >
                  {(id, describedBy) => (
                    <Input id={id} aria-describedby={describedBy} {...form.register(`titles.${locale}`)} />
                  )}
                </FormField>
                <FormField
                  label={t("admin.legal.body")}
                  help={t("admin.legal.body_help")}
                  error={fieldMessage(
                    typeof form.formState.errors.bodies?.message === "string"
                      ? form.formState.errors.bodies.message
                      : undefined,
                  )}
                >
                  {(id, describedBy) => (
                    <Textarea id={id} aria-describedby={describedBy} rows={18} {...form.register(`bodies.${locale}`)} />
                  )}
                </FormField>
              </div>
            ),
          })),
          {
            title: t("admin.legal.note"),
            content: (
              <FormField
                label={t("admin.legal.note")}
                help={t("admin.legal.note_help")}
                error={fieldMessage(form.formState.errors.note?.message, { count: 255 })}
              >
                {(id, describedBy) => <Input id={id} aria-describedby={describedBy} {...form.register("note")} />}
              </FormField>
            ),
          },
          {
            title: t("stepper.review"),
            content: (
              <div className="space-y-4">
                {locales.map((locale) => (
                  <details key={locale} open={locale === "en"}>
                    <summary className="min-h-11 cursor-pointer py-2 font-semibold">
                      {t(`locale.name.${locale}`)}
                      {": "}
                      {values.titles?.[locale]}
                    </summary>
                    <LegalBody body={values.bodies?.[locale] ?? ""} />
                  </details>
                ))}
                {values.note && <p className="text-sm text-muted-foreground">{values.note}</p>}
                <ConfirmDialog
                  destructive={false}
                  trigger={
                    <Button type="button" disabled={create.isPending}>
                      {t("admin.legal.save_publish")}
                    </Button>
                  }
                  title={t("admin.legal.publish_title", { version: (latest?.number ?? 0) + 1 })}
                  description={t("admin.legal.publish_body")}
                  confirmLabel={t("admin.legal.save_publish")}
                  onConfirm={() => submit(true)}
                />
              </div>
            ),
          },
        ]}
      />
      <FormError message={form.formState.errors.root?.message} />
    </section>
  )
}
