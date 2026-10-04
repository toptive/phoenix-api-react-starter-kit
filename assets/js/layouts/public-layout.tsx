import { Link } from "@inertiajs/react"
import type { ReactNode } from "react"
import { useTranslation } from "react-i18next"

import { LocaleSwitcher } from "@/components/app/locale-switcher"
import { Logo } from "@/components/app/logo"
import { buttonVariants } from "@/components/ui/button"
import { usePublicRoutes } from "@/hooks/use-public-routes"
import { useSharedProps } from "@/hooks/use-shared-props"
import { routes } from "@/generated/routes"
import { cn } from "@/lib/utils"

/** Marketing and legal pages: header, content, footer with legal links. */
export function PublicLayout({ children }: { children: ReactNode }) {
  const { t } = useTranslation()
  const { auth, app } = useSharedProps()
  const publicRoutes = usePublicRoutes()

  return (
    <div className="flex min-h-full flex-col">
      <a href="#main" className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-50 focus:rounded-md focus:bg-background focus:px-3 focus:py-2">
        {t("a11y.skip_to_content")}
      </a>
      <header className="border-b border-border/70">
        <div className="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-4 sm:px-6">
          <Logo href={publicRoutes.home()} />
          <nav className="flex min-w-0 items-center gap-1 sm:gap-2">
            <LocaleSwitcher />
            {auth ? (
              <Link href={routes.dashboard.show().url} className={buttonVariants({ size: "sm" })}>
                {t("nav.open_app")}
              </Link>
            ) : (
              <>
                <Link
                  href={routes.session.new().url}
                  className={cn(buttonVariants({ variant: "ghost", size: "sm" }), "hidden sm:inline-flex")}
                >
                  {t("nav.sign_in")}
                </Link>
                <Link href={routes.registration.new().url} className={buttonVariants({ size: "sm" })}>
                  {t("nav.sign_up")}
                </Link>
              </>
            )}
          </nav>
        </div>
      </header>
      <main id="main" className="flex-1">
        {children}
      </main>
      <footer className="border-t border-border/70">
        <div className="mx-auto flex max-w-6xl flex-col gap-4 px-4 py-8 text-sm text-muted-foreground sm:flex-row sm:items-center sm:justify-between sm:px-6">
          <p>{t("footer.copyright", { year: new Date().getFullYear(), app: app.name })}</p>
          <nav aria-label={t("footer.legal")} className="flex flex-wrap gap-x-5 gap-y-2">
            {(["terms", "privacy", "cookies"] as const).map((slug) => (
              <Link key={slug} href={publicRoutes.legal(slug)} className="hover:text-foreground">
                {t(`legal.${slug}`)}
              </Link>
            ))}
          </nav>
        </div>
      </footer>
    </div>
  )
}
