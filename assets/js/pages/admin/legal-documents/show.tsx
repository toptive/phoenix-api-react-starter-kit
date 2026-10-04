import { Head, router, useForm } from "@inertiajs/react"
import { useTranslation } from "react-i18next"

import { ConfirmDialog } from "@/components/app/confirm-dialog"
import { FieldHelp } from "@/components/app/field-help"
import { FormField } from "@/components/app/form-field"
import { PageHeader } from "@/components/app/page-header"
import { StatusBadge } from "@/components/app/status-badge"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Textarea } from "@/components/ui/textarea"
import { formatDateTime } from "@/lib/format"
import { routes } from "@/generated/routes"
import type { AdminLegalDocumentsShowProps } from "@/generated/pages"


export default function AdminLegalShow({ document, locales, locale }: AdminLegalDocumentsShowProps) {
  const { t } = useTranslation()
  const latest = document.versions[0]
  const empty = Object.fromEntries(locales.map((l) => [l, ""]))
  const form = useForm({
    titles: { ...empty, ...(latest?.titles ?? {}) } as Record<string, string>,
    bodies: { ...empty, ...(latest?.bodies ?? {}) } as Record<string, string>,
    note: "",
    publish: false,
  })
  form.transform((data) => ({ version: data }))

  return (
    <>
      <Head title={t(`legal.${document.slug}`)} />
      <PageHeader title={t(`legal.${document.slug}`)} description={t("admin.legal.show_lead")} />

      <div className="grid gap-10 xl:grid-cols-[1.6fr_1fr]">
        <form
          className="grid gap-6"
          onSubmit={(event) => {
            event.preventDefault()
            form.post(routes.adminLegalDocumentLegalDocumentVersion.create(document.slug).url, {
              preserveScroll: true,
              onSuccess: () => form.setData((data) => ({ ...data, note: "", publish: false })),
            })
          }}
        >
          <h2 className="text-lg font-semibold">{t("admin.legal.new_version")}</h2>
          <Tabs defaultValue={locales[0]}>
            <TabsList>
              {locales.map((l) => (
                <TabsTrigger key={l} value={l}>
                  {t(`locale.name.${l}`)}
                </TabsTrigger>
              ))}
            </TabsList>
            {locales.map((l) => (
              <TabsContent key={l} value={l} className="grid gap-4 pt-4">
                <FormField label={t("admin.legal.doc_title")} error={form.errors[`titles`]}>
                  {(id) => <Input id={id} value={form.data.titles[l] ?? ""} onChange={(e) => form.setData("titles", { ...form.data.titles, [l]: e.target.value })} />}
                </FormField>
                <FormField label={t("admin.legal.body")} help={t("admin.legal.body_help")} error={form.errors[`bodies`]}>
                  {(id, describedBy) => (
                    <Textarea id={id} aria-describedby={describedBy} rows={18} value={form.data.bodies[l] ?? ""} onChange={(e) => form.setData("bodies", { ...form.data.bodies, [l]: e.target.value })} />
                  )}
                </FormField>
              </TabsContent>
            ))}
          </Tabs>
          <FormField label={t("admin.legal.note")} help={t("admin.legal.note_help")} error={form.errors.note}>
            {(id, describedBy) => <Input id={id} aria-describedby={describedBy} value={form.data.note} onChange={(e) => form.setData("note", e.target.value)} />}
          </FormField>
          <div className="flex items-center gap-2">
            <Checkbox id="publish" checked={form.data.publish} onCheckedChange={(c) => form.setData("publish", c === true)} />
            <Label htmlFor="publish" className="font-normal">
              {t("admin.legal.publish_now")}
            </Label>
          </div>
          <div>
            <Button type="submit" disabled={form.processing}>
              {form.data.publish ? t("admin.legal.save_publish") : t("admin.legal.save")}
            </Button>
          </div>
        </form>

        <section>
          <h2 className="text-lg font-semibold">{t("admin.legal.versions")}</h2>
          <FieldHelp className="mt-1">{t("admin.legal.versions_help")}</FieldHelp>
          <ul className="mt-4 divide-y rounded-xl border bg-card">
            {document.versions.map((version) => (
              <li key={version.id} className="flex flex-wrap items-center gap-3 p-4">
                <div className="flex-1">
                  <p className="font-medium">{t("admin.legal.version", { version: version.number })}</p>
                  <p className="text-sm text-muted-foreground">
                    {formatDateTime(version.insertedAt, locale)}
                    {version.note ? ` · ${version.note}` : ""}
                  </p>
                </div>
                {version.id === document.publishedVersionId ? (
                  <StatusBadge tone="success">{t("admin.legal.live")}</StatusBadge>
                ) : (
                  <ConfirmDialog
                    destructive={false}
                    trigger={<Button size="sm" variant="outline">{t("admin.legal.publish")}</Button>}
                    title={t("admin.legal.publish_title", { version: version.number })}
                    description={t("admin.legal.publish_body")}
                    confirmLabel={t("admin.legal.publish")}
                    onConfirm={() => router.post(routes.adminLegalDocumentLegalDocumentVersionLegalPublication.create({ legalDocumentSlug: document.slug, legalDocumentVersionNumber: version.number }).url, {}, { preserveScroll: true })}
                  />
                )}
              </li>
            ))}
          </ul>
        </section>
      </div>
    </>
  )
}
