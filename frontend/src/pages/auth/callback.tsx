import { useTranslation } from "react-i18next"
/** Token capture and navigation run in the route loader, before this page renders. */
export default function GoogleCallbackPage() {
  const { t } = useTranslation()
  return <p role="status">{t("auth.callback.loading")}</p>
}
