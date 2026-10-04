import { router } from "@inertiajs/react"
import { SearchIcon } from "lucide-react"
import { useState } from "react"
import { useTranslation } from "react-i18next"

import { Input } from "@/components/ui/input"

/** A search box that reloads the current list with ?q=. */
export function SearchForm({ href, initial, label }: { href: (q: string) => string; initial: string; label: string }) {
  const { t } = useTranslation()
  const [q, setQ] = useState(initial)

  return (
    <form
      role="search"
      className="relative max-w-sm"
      onSubmit={(event) => {
        event.preventDefault()
        router.get(href(q), {}, { preserveState: true })
      }}
    >
      <SearchIcon className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden="true" />
      <Input type="search" aria-label={label} placeholder={t("common.search")} className="pl-9" value={q} onChange={(e) => setQ(e.target.value)} />
    </form>
  )
}
