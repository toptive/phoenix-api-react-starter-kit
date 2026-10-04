import { Link } from "@/components/app/link"
import { ChevronLeftIcon, ChevronRightIcon } from "lucide-react"
import { useTranslation } from "react-i18next"

import { buttonVariants } from "@/components/ui/button"
import type { Pagination as PaginationMeta } from "@/api/generated/serializers"
import { cn } from "@/lib/utils"

/** Previous / next links that keep the current query string. */
export function Pagination({ meta, href }: { meta: PaginationMeta; href: (page: number) => string }) {
  const { t } = useTranslation()
  if (meta.totalPages <= 1) return null

  const link = (page: number, disabled: boolean, label: string, icon: "prev" | "next") =>
    disabled ? (
      <span
        aria-disabled="true"
        className={cn(buttonVariants({ variant: "outline", size: "default" }), "pointer-events-none opacity-50")}
      >
        {icon === "prev" && <ChevronLeftIcon />}
        {label}
        {icon === "next" && <ChevronRightIcon />}
      </span>
    ) : (
      <Link href={href(page)} className={buttonVariants({ variant: "outline", size: "default" })}>
        {icon === "prev" && <ChevronLeftIcon />}
        {label}
        {icon === "next" && <ChevronRightIcon />}
      </Link>
    )

  return (
    <nav aria-label={t("pagination.label")} className="mt-6 flex flex-wrap items-center justify-between gap-4">
      <p className="text-sm text-muted-foreground">
        {t("pagination.summary", { page: meta.page, pages: meta.totalPages, total: meta.total })}
      </p>
      <div className="flex gap-2">
        {link(meta.page - 1, meta.page <= 1, t("pagination.previous"), "prev")}
        {link(meta.page + 1, meta.page >= meta.totalPages, t("pagination.next"), "next")}
      </div>
    </nav>
  )
}
