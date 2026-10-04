import { useNavigate, useLocation } from "@tanstack/react-router"
import { LanguagesIcon } from "lucide-react"
import { useTranslation } from "react-i18next"
import { useAppConfig } from "@/api/hooks/bootstrap"
import { restoreLocale } from "@/api/hooks/locales"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { paths } from "@/lib/paths"

export function LocaleSwitcher() {
  const { t, i18n } = useTranslation()
  const { locales } = useAppConfig()
  const navigate = useNavigate()
  const location = useLocation()
  const go = (next: string) => {
    restoreLocale(next)
    const parts = location.pathname.split("/").filter(Boolean)
    if (locales.includes(parts[0] ?? "")) parts.shift()
    const publicPath =
      parts.length === 0 ? paths.home(next) : parts[0] === "legal" ? paths.legal(parts[1] ?? "terms", next) : null
    void navigate(
      publicPath ? { to: publicPath } : { to: location.pathname, search: { ...location.search, locale: next } },
    )
  }
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="sm">
          <LanguagesIcon aria-hidden="true" />
          <span className="sr-only">{t("locale.label")}</span>
          <span className="uppercase">{i18n.language}</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuRadioGroup value={i18n.language} onValueChange={go}>
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
