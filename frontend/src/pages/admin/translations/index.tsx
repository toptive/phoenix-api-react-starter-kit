import { useRef, useState, type BaseSyntheticEvent } from "react"
import { useSearch, useNavigate } from "@tanstack/react-router"
import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { useTranslation } from "react-i18next"
import { PencilIcon, SparklesIcon, LoaderCircleIcon } from "lucide-react"
import { useAdminTranslations, useUpdateTranslation, useFillTranslations } from "@/api/hooks/admin"
import { useAppConfig } from "@/api/hooks/bootstrap"
import type { TranslationValue } from "@/api/generated/serializers"
import { translationSearchSchema } from "@/schemas/search"
import { translationSchema } from "@/schemas/admin"
import { applyFormErrors, fieldMessage } from "@/lib/form-errors"
import { listHref, listNavigation } from "@/lib/pagination"
import { paths } from "@/lib/paths"
import { PageHeader } from "@/components/app/page-header"
import { SearchForm } from "@/components/app/search-form"
import { Pagination } from "@/components/app/pagination"
import { QueryState } from "@/components/app/query-state"
import { StatusBadge } from "@/components/app/status-badge"
import { FormField } from "@/components/app/form-field"
import { FormError } from "@/components/app/form-error"
import { FieldHelp } from "@/components/app/field-help"
import { Button } from "@/components/ui/button"
import { Textarea } from "@/components/ui/textarea"
import { NativeSelect, NativeSelectOption } from "@/components/ui/native-select"

export default function AdminTranslationsIndex() {
  const { t } = useTranslation()
  const { locales } = useAppConfig()
  const navigate = useNavigate()
  const search = translationSearchSchema.parse(useSearch({ strict: false }))
  const query = useAdminTranslations(search)
  return (
    <>
      <title>{t("admin.translations.title")}</title>
      <PageHeader
        title={t("admin.translations.title")}
        description={t("admin.translations.lead")}
        actions={
          <div className="flex flex-wrap gap-3">
            {locales
              .filter((locale) => locale !== "en")
              .map((locale) => (
                <FillLocale key={locale} locale={locale} />
              ))}
          </div>
        }
      />
      <div className="mb-6 flex flex-wrap items-center gap-3">
        <SearchForm
          key={search.q}
          initial={search.q}
          label={t("admin.translations.search")}
          href={(q) => listHref(paths.adminTranslations, search, { q })}
        />
        <NativeSelect
          className="min-h-11"
          aria-label={t("admin.translations.filter_missing")}
          value={search.missing ?? ""}
          onChange={(event) => {
            void navigate(listNavigation(listHref(paths.adminTranslations, search, { missing: event.target.value })))
          }}
        >
          <NativeSelectOption value="">{t("admin.translations.all")}</NativeSelectOption>
          {locales.map((locale) => (
            <NativeSelectOption key={locale} value={locale}>
              {t("admin.translations.missing_in", { language: t(`locale.name.${locale}`) })}
            </NativeSelectOption>
          ))}
        </NativeSelect>
      </div>
      <QueryState pending={query.isPending} error={query.error} retry={query.refetch} />
      {query.data && (
        <>
          {!query.data.data.length && <p className="text-muted-foreground">{t("admin.empty")}</p>}
          <ul aria-busy={query.isFetching} className="divide-y rounded-xl border bg-card">
            {query.data.data.map((entry) => (
              <li key={entry.key} className="grid gap-3 p-4">
                <code className="text-sm break-all text-muted-foreground">{entry.key}</code>
                <div className="grid gap-3 md:grid-cols-2">
                  {entry.values.map((value) => (
                    <TranslationCell key={`${value.locale}:${value.value}`} translationKey={entry.key} {...value} />
                  ))}
                </div>
              </li>
            ))}
          </ul>
          {query.data.meta?.pagination && (
            <Pagination
              meta={query.data.meta.pagination}
              href={(page) => listHref(paths.adminTranslations, search, { page })}
            />
          )}
        </>
      )}
    </>
  )
}
function FillLocale({ locale }: { locale: string }) {
  const { t } = useTranslation()
  const fill = useFillTranslations()
  return (
    <div className="grid gap-2">
      <Button variant="outline" disabled={fill.isPending} onClick={() => fill.mutate(locale)}>
        {fill.isPending ? (
          <LoaderCircleIcon aria-hidden="true" className="animate-spin motion-reduce:animate-none" />
        ) : (
          <SparklesIcon aria-hidden="true" />
        )}
        {t("admin.translations.fill", { language: t(`locale.name.${locale}`) })}
      </Button>
      {fill.data && (
        <p role="status" className="text-sm">
          {t("flash.admin.translations_filled", { count: fill.data.count })}
        </p>
      )}
      <FormError error={fill.error} />
    </div>
  )
}
function TranslationCell({ translationKey, locale, value, edited }: TranslationValue & { translationKey: string }) {
  const { t } = useTranslation()
  const [editing, setEditing] = useState(false)
  const busy = useRef(false)
  const update = useUpdateTranslation()
  const form = useForm({ resolver: zodResolver(translationSchema), defaultValues: { locale, value } })
  const save = (event?: BaseSyntheticEvent) =>
    form.handleSubmit(async (input) => {
      if (busy.current) return
      if (input.value === value) {
        setEditing(false)
        return
      }
      busy.current = true
      try {
        await update.mutateAsync({ key: translationKey, ...input })
        setEditing(false)
      } catch (error) {
        applyFormErrors(error, form.setError)
      } finally {
        busy.current = false
      }
    })(event)
  if (!editing)
    return (
      <div className="group rounded-lg border border-transparent p-2 hover:border-border">
        <div className="mb-1 flex items-center gap-2">
          <span className="text-xs font-semibold text-muted-foreground uppercase">{locale}</span>
          {edited && <StatusBadge tone="info">{t("admin.translations.edited")}</StatusBadge>}
          {!value && <StatusBadge tone="warning">{t("admin.translations.empty")}</StatusBadge>}
          <Button
            variant="ghost"
            className="ml-auto min-h-11 min-w-11"
            onClick={() => setEditing(true)}
            aria-label={t("admin.translations.edit", { key: translationKey, locale })}
          >
            <PencilIcon aria-hidden="true" />
          </Button>
        </div>
        <p className="text-sm whitespace-pre-wrap">{value}</p>
      </div>
    )
  return (
    <form className="grid gap-2 rounded-lg border p-2" onSubmit={save}>
      <FormField
        label={t(`locale.name.${locale}`)}
        error={fieldMessage(form.formState.errors.value?.message, { count: 20_000 })}
      >
        {(id, describedBy) => (
          <Textarea
            autoFocus
            id={id}
            aria-describedby={describedBy}
            rows={3}
            disabled={update.isPending}
            {...form.register("value")}
            onBlur={() => {
              void save()
            }}
            onKeyDown={(event) => {
              if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing) {
                event.preventDefault()
                void save()
              }
            }}
          />
        )}
      </FormField>
      <FieldHelp>{t("admin.translations.inline_help")}</FieldHelp>
      <FieldHelp>{t("admin.translations.placeholder_help")}</FieldHelp>
      <FormError message={form.formState.errors.root?.message} />
      <Button type="submit" variant="outline" disabled={update.isPending}>
        {t(update.isPending ? "common.saving" : "common.save")}
      </Button>
    </form>
  )
}
