import { useEffect, useRef } from "react"
import { useSearch } from "@tanstack/react-router"
import { useForm, useWatch } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { Trans, useTranslation } from "react-i18next"
import { toast } from "sonner"
import { useBilling, useCheckout, useBillingPortal } from "@/api/hooks/billing"
import { ApiError } from "@/api/http"
import ErrorShow from "@/pages/errors/show"
import type { BillingOverview, Subscription } from "@/api/generated/serializers"
import { billingSearchSchema } from "@/schemas/search"
import { checkoutSchema } from "@/schemas/billing"
import { applyFormErrors, fieldMessage } from "@/lib/form-errors"
import { formatDate, formatMoney } from "@/lib/format"
import { paths } from "@/lib/paths"
import { SettingsSection } from "@/components/app/settings-section"
import { AlertBanner } from "@/components/app/alert-banner"
import { QueryState } from "@/components/app/query-state"
import { FormError } from "@/components/app/form-error"
import { Link } from "@/components/app/link"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import { Label } from "@/components/ui/label"

function statusKey(subscription: Subscription): string {
  if (subscription.paused) return "billing.status.paused"
  if (subscription.status === "past_due") return "billing.status.past_due"
  if (!subscription.paid) return "billing.status.ended"
  return subscription.cancelAtPeriodEnd ? "billing.status.ends" : "billing.status.renews"
}
export default function BillingShow() {
  const { t, i18n } = useTranslation()
  const portal = useBillingPortal()
  const { checkout } = billingSearchSchema.parse(useSearch({ strict: false }))
  const query = useBilling(checkout === "done")
  const announced = useRef(false)
  useEffect(() => {
    if (checkout === "done" && !announced.current) {
      announced.current = true
      toast.success(t("billing.return.confirming"))
    }
  }, [checkout, t])
  if (query.error instanceof ApiError && query.error.status === 404) return <ErrorShow status={404} />
  if (!query.data) return <QueryState pending={query.isPending} error={query.error} retry={query.refetch} />
  const { plan, subscription, offers, sales, canManage } = query.data
  const paid = subscription?.paid === true
  return (
    <SettingsSection title={t("settings.billing.title")} description={t("settings.billing.lead")}>
      <title>{t("settings.billing.title")}</title>
      <div className="space-y-6">
        {checkout === "done" && (
          <AlertBanner
            tone={paid ? "success" : "info"}
            title={t(paid ? "billing.return.active" : "billing.return.confirming")}
            action={
              !paid && (
                <Button
                  variant="outline"
                  disabled={query.isFetching}
                  onClick={() => {
                    void query.refetch()
                  }}
                >
                  {t("billing.return.check_again")}
                </Button>
              )
            }
          >
            {!paid && t("billing.return.confirming_help")}
          </AlertBanner>
        )}
        {sales === "test" && (
          <AlertBanner tone="warning" title={t("billing.test_mode.title")}>
            {t("billing.test_mode.body")}
          </AlertBanner>
        )}
        <div className="rounded-xl border p-5">
          <p className="text-sm text-muted-foreground">{t("billing.current_plan")}</p>
          <p className="mt-1 text-2xl font-bold">{t(`billing.plan.${plan}`, { defaultValue: plan })}</p>
          {subscription && (
            <p className="mt-2 text-sm">
              {t(statusKey(subscription), { date: formatDate(subscription.currentPeriodEnd, i18n.language) })}
            </p>
          )}
        </div>
        {subscription && canManage && (
          <div className="space-y-2">
            <Button
              variant={paid ? "default" : "outline"}
              disabled={portal.isPending}
              onClick={() => portal.mutate(undefined, { onSuccess: ({ url }) => window.location.assign(url) })}
            >
              {t("billing.portal.open")}
            </Button>
            <p className="text-sm text-muted-foreground">{t("billing.portal.help")}</p>
            <FormError error={portal.error} />
          </div>
        )}
        {!canManage && <AlertBanner title={t("billing.read_only")}>{t("billing.read_only_help")}</AlertBanner>}
        {!paid && sales === "closed" && <AlertBanner title={t("billing.closed")} />}
        {!paid && offers.length > 0 && <OfferForm key={query.data.offerRevision} overview={query.data} />}
      </div>
    </SettingsSection>
  )
}
function OfferForm({ overview }: { overview: BillingOverview }) {
  const { t, i18n } = useTranslation()
  const checkout = useCheckout()
  const { offers, offerRevision, canManage, sales } = overview
  const form = useForm({
    resolver: zodResolver(checkoutSchema),
    defaultValues: { offerId: offers[0]?.id ?? "", offerRevision, accepted: false },
  })
  const values = useWatch({ control: form.control })
  const selected = offers.find((offer) => offer.id === values.offerId)
  const canBuy = canManage && sales !== "closed"
  return (
    <form
      noValidate
      className="grid gap-6 pt-4"
      onSubmit={form.handleSubmit(async (input) => {
        if (!canBuy) return
        try {
          const { url } = await checkout.mutateAsync(input)
          window.location.assign(url)
        } catch (error) {
          applyFormErrors(error, form.setError)
        }
      })}
    >
      <fieldset className="space-y-4" disabled={!canBuy || checkout.isPending}>
        <legend className="mb-4 text-lg font-semibold">{t("billing.offers.title")}</legend>
        <div className="grid gap-3 sm:grid-cols-2">
          {offers.map((offer) => (
            <label
              key={offer.id}
              className="flex min-h-11 cursor-pointer items-start gap-3 rounded-xl border p-4 has-[:checked]:border-primary"
            >
              <input
                type="radio"
                value={offer.id}
                className="mt-1 size-5 accent-primary"
                {...form.register("offerId")}
                onChange={(event) => {
                  void form.register("offerId").onChange(event)
                  form.setValue("accepted", false)
                }}
              />
              <span className="space-y-1">
                <span className="block font-semibold">
                  {t(`billing.plan.${offer.plan}`, { defaultValue: offer.plan })}
                  {" · "}
                  {t(`billing.interval.${offer.interval}`)}
                </span>
                <span className="block text-xl font-bold">
                  {formatMoney(offer.amountCents, offer.currency, i18n.language)}{" "}
                  <span className="text-sm font-normal text-muted-foreground">
                    {t(`billing.per.${offer.interval}`)}
                  </span>
                </span>
                <span className="block text-sm text-muted-foreground">{t(`billing.plan_summary.${offer.plan}`)}</span>
              </span>
            </label>
          ))}
        </div>
      </fieldset>
      <FormError message={fieldMessage(form.formState.errors.offerId?.message)} />
      <FormError message={fieldMessage(form.formState.errors.offerRevision?.message)} />
      {canBuy && selected && (
        <>
          <div className="flex items-start gap-3">
            <Checkbox
              id="billing-accepted"
              className="mt-3"
              checked={values.accepted}
              disabled={checkout.isPending}
              onCheckedChange={(checked) => form.setValue("accepted", checked === true, { shouldValidate: true })}
              aria-describedby="billing-accept-error"
            />
            <Label htmlFor="billing-accepted" className="min-h-11 py-2 leading-relaxed font-normal">
              <span>
                <Trans
                  i18nKey="billing.accept"
                  values={{
                    price: formatMoney(selected.amountCents, selected.currency, i18n.language),
                    period: t(`billing.per.${selected.interval}`),
                  }}
                  components={{
                    terms: <Link className="underline underline-offset-4" href={paths.legal("terms", i18n.language)} />,
                    privacy: (
                      <Link className="underline underline-offset-4" href={paths.legal("privacy", i18n.language)} />
                    ),
                  }}
                />
              </span>
            </Label>
          </div>
          <div id="billing-accept-error">
            <FormError message={fieldMessage(form.formState.errors.accepted?.message)} />
          </div>
          <FormError message={form.formState.errors.root?.message} />
          <div className="space-y-2">
            <Button type="submit" size="lg" disabled={checkout.isPending}>
              {t("billing.checkout.submit", {
                price: formatMoney(selected.amountCents, selected.currency, i18n.language),
              })}
            </Button>
            <p className="text-sm text-muted-foreground">{t("billing.price_note")}</p>
          </div>
        </>
      )}
    </form>
  )
}
