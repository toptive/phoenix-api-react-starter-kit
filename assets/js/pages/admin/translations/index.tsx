import { Head, router } from "@inertiajs/react"
import { PencilIcon, SparklesIcon } from "lucide-react"
import { useState } from "react"
import { useTranslation } from "react-i18next"

import { ConfirmDialog } from "@/components/app/confirm-dialog"
import { FieldHelp } from "@/components/app/field-help"
import { PageHeader } from "@/components/app/page-header"
import { Pagination } from "@/components/app/pagination"
import { SearchForm } from "@/components/app/search-form"
import { StatusBadge } from "@/components/app/status-badge"
import { Button } from "@/components/ui/button"
import { NativeSelect, NativeSelectOption } from "@/components/ui/native-select"
import { Textarea } from "@/components/ui/textarea"
import { routes } from "@/generated/routes"
import { compact } from "@/lib/query"
import type { AdminTranslationsIndexProps } from "@/generated/pages"


/** Every text of the app, per language. Edits go live at once and survive deploys. */
export default function AdminTranslationsIndex({ entries, pagination, filters, locales }: AdminTranslationsIndexProps) {
  const { t } = useTranslation()
  const others = locales.slice(1)

  return (
    <>
      <Head title={t("admin.translations.title")} />
      <PageHeader
        title={t("admin.translations.title")}
        description={t("admin.translations.lead")}
        actions={others.map((locale) => (
          <ConfirmDialog
            key={locale}
            destructive={false}
            trigger={
              <Button variant="outline">
                <SparklesIcon aria-hidden="true" /> {t("admin.translations.fill", { language: t(`locale.name.${locale}`) })}
              </Button>
            }
            title={t("admin.translations.fill_title", { language: t(`locale.name.${locale}`) })}
            description={t("admin.translations.fill_body")}
            confirmLabel={t("admin.translations.fill", { language: t(`locale.name.${locale}`) })}
            onConfirm={() => router.post(routes.adminTranslationFill.create().url, { translationFill: { locale } })}
          />
        ))}
      />

      <div className="mb-6 flex flex-wrap items-center gap-3">
        <SearchForm
          href={(query) => routes.adminTranslation.index({ query: compact({ q: query, missing: filters.missing }) }).url}
          initial={filters.q}
          label={t("admin.translations.search")}
        />
        <NativeSelect
          aria-label={t("admin.translations.filter_missing")}
          value={filters.missing}
          onChange={(e) => router.get(routes.adminTranslation.index({ query: compact({ q: filters.q, missing: e.target.value }) }).url)}
        >
          <NativeSelectOption value="">{t("admin.translations.all")}</NativeSelectOption>
          {locales.map((locale) => (
            <NativeSelectOption key={locale} value={locale}>
              {t("admin.translations.missing_in", { language: t(`locale.name.${locale}`) })}
            </NativeSelectOption>
          ))}
        </NativeSelect>
      </div>

      <ul className="divide-y rounded-xl border bg-card">
        {entries.map((entry) => (
          <li key={entry.key} className="grid gap-3 p-4">
            <code className="text-sm text-muted-foreground">{entry.key}</code>
            <div className="grid gap-3 md:grid-cols-2">
              {entry.values.map((value) => (
                <TranslationCell key={value.locale} translationKey={entry.key} filters={filters} page={pagination.page} {...value} />
              ))}
            </div>
          </li>
        ))}
      </ul>
      <Pagination meta={pagination} href={(page) => routes.adminTranslation.index({ query: compact({ ...filters, page }) }).url} />
    </>
  )
}

function TranslationCell({
  translationKey,
  locale,
  value,
  edited,
  filters,
  page,
}: {
  translationKey: string
  locale: string
  value: string
  edited: boolean
  filters: { q: string; missing: string }
  page: number
}) {
  const { t } = useTranslation()
  const [draft, setDraft] = useState<string | null>(null)

  if (draft === null) {
    return (
      <div className="group rounded-lg border border-transparent p-2 hover:border-border">
        <div className="mb-1 flex items-center gap-2">
          <span className="text-xs font-semibold uppercase text-muted-foreground">{locale}</span>
          {edited && <StatusBadge tone="info">{t("admin.translations.edited")}</StatusBadge>}
          {value === "" && <StatusBadge tone="warning">{t("admin.translations.empty")}</StatusBadge>}
          <Button variant="ghost" size="sm" className="ml-auto" onClick={() => setDraft(value)} aria-label={t("admin.translations.edit", { key: translationKey, locale })}>
            <PencilIcon aria-hidden="true" />
          </Button>
        </div>
        <p className="whitespace-pre-wrap text-sm">{value}</p>
      </div>
    )
  }

  return (
    <form
      className="grid gap-2 rounded-lg border p-2"
      onSubmit={(event) => {
        event.preventDefault()
        router.put(
          routes.adminTranslation.update(translationKey, { query: compact({ ...filters, page }) }).url,
          { translation: { locale, value: draft } },
          { preserveScroll: true, onSuccess: () => setDraft(null) },
        )
      }}
    >
      <span className="text-xs font-semibold uppercase text-muted-foreground">{locale}</span>
      <Textarea autoFocus rows={3} value={draft} onChange={(e) => setDraft(e.target.value)} />
      <FieldHelp>{t("admin.translations.placeholder_help")}</FieldHelp>
      <div className="flex gap-2">
        <Button type="submit" size="sm">
          {t("common.save")}
        </Button>
        <Button type="button" size="sm" variant="ghost" onClick={() => setDraft(null)}>
          {t("common.cancel")}
        </Button>
      </div>
    </form>
  )
}
