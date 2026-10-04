import { MonitorIcon, MoonIcon, SunIcon } from "lucide-react"
import { useTranslation } from "react-i18next"

import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { type Appearance, useAppearance } from "@/hooks/use-appearance"

const options = [
  { value: "light", icon: SunIcon },
  { value: "dark", icon: MoonIcon },
  { value: "system", icon: MonitorIcon },
] as const

/** Light / dark / follow the device. Stored in this browser only. */
export function AppearanceToggle() {
  const { t } = useTranslation()
  const { appearance, setAppearance } = useAppearance()

  return (
    <ToggleGroup
      type="single"
      variant="outline"
      value={appearance}
      onValueChange={(value) => value && setAppearance(value as Appearance)}
      aria-label={t("appearance.label")}
    >
      {options.map(({ value, icon: Icon }) => (
        <ToggleGroupItem key={value} value={value} className="gap-2 px-4">
          <Icon aria-hidden="true" />
          {t(`appearance.${value}`)}
        </ToggleGroupItem>
      ))}
    </ToggleGroup>
  )
}
