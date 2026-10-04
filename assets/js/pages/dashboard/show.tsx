import { Head, Link } from "@inertiajs/react"
import { CheckCircle2Icon, CircleIcon, SparklesIcon } from "lucide-react"
import { useTranslation } from "react-i18next"

import { EmptyState } from "@/components/app/empty-state"
import { PageHeader } from "@/components/app/page-header"
import { routes } from "@/generated/routes"
import type { DashboardShowProps } from "@/generated/pages"

/** The product's home. Products replace the empty state with their main task. */
export default function DashboardShow({ auth }: DashboardShowProps) {
  const { t } = useTranslation()
  if (!auth) return null
  const firstName = auth.user.name.split(" ")[0] || auth.user.email
  const canInvite = ["owner", "admin"].includes(auth.membership.role) && auth.membership.access === "full"

  const checklist = [
    { done: auth.user.name !== "", label: t("dashboard.checklist.profile"), href: routes.settingsProfile.edit().url },
    { done: auth.user.hasPassword, label: t("dashboard.checklist.password"), href: routes.settingsPassword.edit().url },
    ...(canInvite ? [{ done: false, label: t("dashboard.checklist.invite"), href: routes.settingsMembership.index().url }] : []),
  ]

  return (
    <>
      <Head title={t("dashboard.title")} />
      <PageHeader title={t("dashboard.greeting", { name: firstName })} description={t("dashboard.lead", { organization: auth.organization.name })} />

      <div className="grid gap-8 lg:grid-cols-[1.6fr_1fr]">
        <EmptyState icon={SparklesIcon} title={t("dashboard.empty.title")} description={t("dashboard.empty.body")} />

        <section aria-labelledby="checklist" className="rounded-xl border bg-card p-6">
          <h2 id="checklist" className="font-semibold">{t("dashboard.checklist.title")}</h2>
          <ul className="mt-4 space-y-3">
            {checklist.map((item) => (
              <li key={item.href} className="flex items-center gap-3">
                {item.done ? (
                  <CheckCircle2Icon className="size-5 text-primary" aria-label={t("dashboard.checklist.done")} />
                ) : (
                  <CircleIcon className="size-5 text-muted-foreground" aria-label={t("dashboard.checklist.todo")} />
                )}
                <Link href={item.href} className={item.done ? "text-muted-foreground line-through" : "font-medium hover:underline"}>
                  {item.label}
                </Link>
              </li>
            ))}
          </ul>
        </section>
      </div>
    </>
  )
}
