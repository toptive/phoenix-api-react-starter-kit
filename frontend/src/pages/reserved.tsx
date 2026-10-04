import { FileTextIcon } from "lucide-react"
import { useTranslation } from "react-i18next"
import { EmptyState } from "@/components/app/empty-state"
/** Routes for later SPA tasks retain their guards and layout. */
export default function ReservedPage() {
  const { t } = useTranslation()
  return <EmptyState icon={FileTextIcon} title={t("spa.page_pending.title")} description={t("spa.page_pending.body")} />
}
