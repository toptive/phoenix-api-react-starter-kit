import { router, usePage } from "@inertiajs/react"
import { LanguagesIcon } from "lucide-react"
import { useTranslation } from "react-i18next"

import { Button } from "@/components/ui/button"
import { DropdownMenu, DropdownMenuContent, DropdownMenuRadioGroup, DropdownMenuRadioItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"
import type { SharedProps } from "@/generated/pages"

type WithSeo = SharedProps & { seo?: { alternates: { hreflang: string; href: string }[] } }

/**
 * Language picker for public and sign-in pages. Public pages go to their localized URL
 * (/es/…); other pages reload with ?locale= (remembered in the session). Signed-in
 * users change their language in Settings → Profile.
 */
export function LocaleSwitcher() {
  const { t } = useTranslation()
  const { locale, locales, seo } = usePage().props as unknown as WithSeo

  const go = (next: string) => {
    const alternate = seo?.alternates.find((alt) => alt.hreflang === next)
    if (alternate) {
      router.visit(new URL(alternate.href).pathname)
    } else {
      const url = new URL(window.location.href)
      url.searchParams.set("locale", next)
      router.visit(url.pathname + url.search, { preserveScroll: true })
    }
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="sm">
          <LanguagesIcon aria-hidden="true" />
          <span className="sr-only">{t("locale.label")}:</span>
          <span className="uppercase">{locale}</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuRadioGroup value={locale} onValueChange={go}>
          {locales.map((code) => (
            <DropdownMenuRadioItem key={code} value={code}>
              {t(`locale.name.${code}`)}
            </DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
