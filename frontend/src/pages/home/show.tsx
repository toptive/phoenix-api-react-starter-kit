import { Link } from "@/components/app/link"
import { ArrowLeftIcon, CheckIcon } from "lucide-react"
import { useTranslation } from "react-i18next"

import { FieldHelp } from "@/components/app/field-help"
import { Seo } from "@/components/app/seo"
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion"
import { buttonVariants } from "@/components/ui/button"
import { paths } from "@/lib/paths"
import { cn } from "@/lib/utils"
import { useAppConfig } from "@/api/hooks/bootstrap"

export default function HomeShow() {
  const { t } = useTranslation()
  const { auth, app, locales } = useAppConfig()
  const registrationAvailable = app.emailAvailable && app.signupMode !== "closed"
  const startLabel = auth ? t("nav.open_app") : registrationAvailable ? t("home.hero.cta_primary") : t("nav.sign_in")
  const start = auth
    ? paths.dashboard
    : app.signupMode === "closed" || !app.emailAvailable
      ? paths.signIn
      : paths.register

  return (
    <>
      <Seo title={t("home.hero.title")} description={t("home.hero.lead")} publicUrl={app.publicUrl} locales={locales} />

      <section className="mx-auto grid max-w-6xl items-center gap-12 px-4 pt-12 pb-20 sm:px-6 lg:grid-cols-[1.1fr_1fr] lg:pt-20">
        <div>
          <h1 className="max-w-xl text-4xl leading-[1.05] font-extrabold sm:text-6xl">{t("home.hero.title")}</h1>
          <p className="mt-6 max-w-lg text-lg leading-8 text-muted-foreground">{t("home.hero.lead")}</p>
          <div className="mt-8 flex flex-wrap items-center gap-3">
            <Link href={start} className={buttonVariants({ size: "lg" })}>
              {startLabel}
            </Link>
            {!auth && registrationAvailable && (
              <Link href={paths.signIn} className={buttonVariants({ size: "lg", variant: "ghost" })}>
                {t("home.hero.cta_secondary")}
              </Link>
            )}
          </div>
          <p className="mt-4 text-sm text-muted-foreground">{t("home.hero.note")}</p>
        </div>
        <StepDemo />
      </section>

      <section aria-labelledby="how" className="border-y bg-card">
        <div className="mx-auto max-w-6xl px-4 py-20 sm:px-6">
          <h2 id="how" className="text-3xl font-bold">
            {t("home.how.title")}
          </h2>
          <ol className="mt-10 grid gap-10 md:grid-cols-3">
            {[1, 2, 3].map((n) => (
              <li key={n} className="flex gap-4">
                <span
                  aria-hidden="true"
                  className="flex size-9 shrink-0 items-center justify-center rounded-full bg-primary text-sm font-bold text-primary-foreground"
                >
                  {n}
                </span>
                <div>
                  <h3 className="text-lg font-semibold">{t(`home.how.step${n}.title`)}</h3>
                  <p className="mt-2 leading-7 text-muted-foreground">{t(`home.how.step${n}.body`)}</p>
                </div>
              </li>
            ))}
          </ol>
        </div>
      </section>

      <section aria-labelledby="values" className="mx-auto max-w-6xl px-4 py-20 sm:px-6">
        <h2 id="values" className="max-w-xl text-3xl font-bold">
          {t("home.values.title")}
        </h2>
        <dl className="mt-10 grid gap-x-12 gap-y-8 sm:grid-cols-2">
          {["plain", "privacy", "language", "help"].map((key) => (
            <div key={key} className="border-l-2 border-primary/40 pl-5">
              <dt className="font-semibold">{t(`home.values.${key}.title`)}</dt>
              <dd className="mt-1 leading-7 text-muted-foreground">{t(`home.values.${key}.body`)}</dd>
            </div>
          ))}
        </dl>
      </section>

      <section aria-labelledby="faq" className="border-t bg-card">
        <div className="mx-auto grid max-w-6xl gap-10 px-4 py-20 sm:px-6 lg:grid-cols-[1fr_1.6fr]">
          <h2 id="faq" className="text-3xl font-bold">
            {t("home.faq.title")}
          </h2>
          <Accordion type="single" collapsible className="w-full">
            {[1, 2, 3, 4].map((n) => (
              <AccordionItem key={n} value={`q${n}`}>
                <AccordionTrigger className="text-base">{t(`home.faq.q${n}`)}</AccordionTrigger>
                <AccordionContent className="text-base leading-7 text-muted-foreground">
                  {t(`home.faq.a${n}`)}
                </AccordionContent>
              </AccordionItem>
            ))}
          </Accordion>
        </div>
      </section>

      <section className="mx-auto max-w-6xl px-4 py-20 text-center sm:px-6">
        <h2 className="text-3xl font-bold">{t("home.final.title")}</h2>
        <p className="mx-auto mt-3 max-w-md text-muted-foreground">{t("home.final.body")}</p>
        <Link href={start} className={cn(buttonVariants({ size: "lg" }), "mt-8")}>
          {startLabel}
        </Link>
      </section>
    </>
  )
}

/** The product in one picture: a step of a guided form, with help in place. Illustrative only. */
function StepDemo() {
  const { t } = useTranslation()

  return (
    <figure aria-label={t("home.demo.label")} className="relative mx-auto w-full max-w-md">
      <div className="rounded-2xl border bg-card p-6 shadow-[0_1px_0_var(--border),0_24px_48px_-24px_color-mix(in_oklch,var(--foreground)_25%,transparent)] sm:p-8">
        <div className="flex items-center justify-between text-sm text-muted-foreground">
          <span>{t("home.demo.progress")}</span>
          <span className="flex gap-1" aria-hidden="true">
            {[0, 1, 2, 3].map((i) => (
              <span key={i} className={cn("h-1.5 w-8 rounded-full", i < 2 ? "bg-primary" : "bg-muted")} />
            ))}
          </span>
        </div>
        <p className="mt-6 text-xl font-semibold">{t("home.demo.question")}</p>
        <div className="mt-5 grid gap-2">
          <span className="text-sm font-medium">{t("home.demo.field")}</span>
          <div className="rounded-lg border border-input bg-background px-3 py-2.5 outline-3 outline-offset-2 outline-highlight">
            {t("home.demo.value")}
            <span
              aria-hidden="true"
              className="ml-0.5 inline-block h-5 w-px translate-y-1 animate-pulse bg-foreground"
            />
          </div>
          <FieldHelp>{t("home.demo.help")}</FieldHelp>
        </div>
        <div className="mt-8 flex items-center justify-between">
          <span className="inline-flex items-center gap-1 text-sm text-muted-foreground">
            <ArrowLeftIcon className="size-4" aria-hidden="true" /> {t("stepper.back")}
          </span>
          <span className={buttonVariants({ size: "sm" })}>{t("stepper.next")}</span>
        </div>
      </div>
      <figcaption className="mt-4 flex items-center justify-center gap-2 text-sm text-muted-foreground">
        <CheckIcon className="size-4 text-primary" aria-hidden="true" /> {t("home.demo.caption")}
      </figcaption>
    </figure>
  )
}
