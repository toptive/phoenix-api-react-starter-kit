import { useTranslation } from "react-i18next"
import { AppearanceToggle } from "@/components/app/appearance-toggle"
import { SettingsSection } from "@/components/app/settings-section"

export default function AppearanceEdit() {
  const { t } = useTranslation()
  return (
    <SettingsSection title={t("settings.appearance.title")} description={t("settings.appearance.lead")}>
      <title>{t("settings.appearance.title")}</title>
      <AppearanceToggle />
    </SettingsSection>
  )
}
