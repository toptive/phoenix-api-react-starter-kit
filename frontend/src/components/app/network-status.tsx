import { useEffect } from "react"
import { toast } from "sonner"
import { useTranslation } from "react-i18next"
export function NetworkStatus() {
  const { t } = useTranslation()
  useEffect(() => {
    const offline = () => toast.error(t("errors.offline"), { id: "network-status", duration: Infinity })
    const online = () => toast.success(t("errors.online"), { id: "network-status" })
    window.addEventListener("offline", offline)
    window.addEventListener("online", online)
    if (!navigator.onLine) offline()
    return () => {
      window.removeEventListener("offline", offline)
      window.removeEventListener("online", online)
    }
  }, [t])
  return null
}
