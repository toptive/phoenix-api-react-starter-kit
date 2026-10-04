import { Head, Link, router, useForm } from "@inertiajs/react"
import { Trans, useTranslation } from "react-i18next"

import { AlertBanner } from "@/components/app/alert-banner"
import { SettingsSection } from "@/components/app/settings-section"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import { Label } from "@/components/ui/label"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { formatDate, formatMoney } from "@/lib/format"
import { routes } from "@/generated/routes"
import { usePublicRoutes } from "@/hooks/use-public-routes"
import type { Offer, Subscription } from "@/generated/serializers"
import type { SettingsBillingShowProps } from "@/generated/pages"

/** "What plan are we on, and how do we pay, change or cancel?" */
export default function BillingShow({ plan, subscription, offers, offerRevision, sales, canManage, fromCheckout, locale }: SettingsBillingShowProps) {
  const { t } = useTranslation()
  const portal = useForm({})
  const paid = subscription?.paid === true

  return (
    <SettingsSection title={t("settings.billing.title")} description={t("settings.billing.lead")}>
      <Head title={t("settings.billing.title")} />

      {fromCheckout &&
        (paid ? (
          <AlertBanner tone="success" className="mb-6" title={t("billing.return.active")} />
        ) : (
          <AlertBanner
            className="mb-6"
            title={t("billing.return.confirming")}
            action={
              <Button variant="outline" size="sm" onClick={() => router.reload()}>
                {t("billing.return.check_again")}
              </Button>
            }
          >
            {t("billing.return.confirming_help")}
          </AlertBanner>
        ))}

      <CurrentPlan plan={plan} subscription={subscription} locale={locale} />

      {subscription && canManage && (
        <div className="mt-6 space-y-2">
          <Button variant={paid ? "default" : "outline"} disabled={portal.processing} onClick={() => portal.post(routes.settingsBillingPortalSession.create().url)}>
            {t("billing.portal.open")}
          </Button>
          <p className="text-sm text-muted-foreground">{t("billing.portal.help")}</p>
        </div>
      )}

      {!canManage && (
        <AlertBanner className="mt-6" title={t("billing.read_only")}>
          {t("billing.read_only_help")}
        </AlertBanner>
      )}

      {!paid && sales === "closed" && offers.length > 0 && <AlertBanner className="mt-8" title={t("billing.closed")} />}

      {!paid && sales !== "closed" && offers.length > 0 && (
        <OfferForm offers={offers} offerRevision={offerRevision} testMode={sales === "test"} canManage={canManage} locale={locale} />
      )}
    </SettingsSection>
  )
}

function CurrentPlan({ plan, subscription, locale }: { plan: string; subscription: Subscription | null; locale: string }) {
  const { t } = useTranslation()
  const date = formatDate(subscription?.currentPeriodEnd, locale)

  return (
    <div className="rounded-xl border p-5">
      <p className="text-sm text-muted-foreground">{t("billing.current_plan")}</p>
      <p className="mt-1 text-2xl font-bold">{t(`billing.plan.${plan}`)}</p>
      {subscription && <p className="mt-2 text-sm">{t(statusKey(subscription), { date })}</p>}
    </div>
  )
}

/** One sentence that says what happens next with the subscription. */
function statusKey(subscription: Subscription): string {
  if (subscription.paused) return "billing.status.paused"
  if (subscription.status === "past_due") return "billing.status.past_due"
  if (!subscription.paid) return "billing.status.ended"
  return subscription.cancelAtPeriodEnd ? "billing.status.ends" : "billing.status.renews"
}

function OfferForm({ offers, offerRevision, testMode, canManage, locale }: { offers: Offer[]; offerRevision: string; testMode: boolean; canManage: boolean; locale: string }) {
  const { t } = useTranslation()
  const publicRoutes = usePublicRoutes()
  const form = useForm({ offerId: offers[0]?.id ?? "", offerRevision, accepted: false })
  form.transform((data) => ({ checkout: data }))

  const selected = offers.find((offer) => offer.id === form.data.offerId)
  const price = (offer: Offer) => formatMoney(offer.amountCents, offer.currency.toUpperCase(), locale)
  const legalLink = "underline underline-offset-4"

  return (
    <form
      className="mt-10 grid gap-6"
      onSubmit={(event) => {
        event.preventDefault()
        form.post(routes.settingsBillingCheckoutSession.create().url)
      }}
    >
      <h2 className="text-lg font-semibold">{t("billing.offers.title")}</h2>

      {testMode && (
        <AlertBanner tone="warning" title={t("billing.test_mode.title")}>
          {t("billing.test_mode.body")}
        </AlertBanner>
      )}

      <RadioGroup value={form.data.offerId} onValueChange={(value) => form.setData("offerId", value)} disabled={!canManage} className="gap-3 sm:grid-cols-2">
        {offers.map((offer) => (
          <Label
            key={offer.id}
            htmlFor={`offer-${offer.id}`}
            className="flex min-h-11 cursor-pointer items-start gap-3 rounded-xl border p-4 font-normal has-[[data-state=checked]]:border-primary"
          >
            <RadioGroupItem id={`offer-${offer.id}`} value={offer.id} className="mt-1" />
            <span className="space-y-1">
              <span className="block font-semibold">
                {t(`billing.plan.${offer.plan}`)} · {t(`billing.interval.${offer.interval}`)}
              </span>
              <span className="block text-xl font-bold">
                {price(offer)} <span className="text-sm font-normal text-muted-foreground">{t(`billing.per.${offer.interval}`)}</span>
              </span>
              <span className="block text-sm text-muted-foreground">{t(`billing.plan_summary.${offer.plan}`)}</span>
            </span>
          </Label>
        ))}
      </RadioGroup>

      {canManage && selected && (
        <>
          <div className="flex items-start gap-3">
            <Checkbox id="accepted" required className="mt-0.5" checked={form.data.accepted} onCheckedChange={(checked) => form.setData("accepted", checked === true)} />
            <Label htmlFor="accepted" className="block font-normal leading-relaxed">
              <Trans
                i18nKey="billing.accept"
                values={{ price: price(selected), period: t(`billing.per.${selected.interval}`) }}
                components={{
                  terms: <Link href={publicRoutes.legal("terms")} className={legalLink} />,
                  privacy: <Link href={publicRoutes.legal("privacy")} className={legalLink} />,
                }}
              />
            </Label>
          </div>
          <div className="space-y-2">
            <Button type="submit" size="lg" disabled={form.processing}>
              {t("billing.checkout.submit", { price: price(selected) })}
            </Button>
            <p className="text-sm text-muted-foreground">{t("billing.price_note")}</p>
          </div>
        </>
      )}
    </form>
  )
}
