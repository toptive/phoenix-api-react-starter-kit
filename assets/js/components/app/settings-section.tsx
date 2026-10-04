import type { ReactNode } from "react"

/** One settings page: title, what it changes, then the form. */
export function SettingsSection({ title, description, children }: { title: string; description: string; children: ReactNode }) {
  return (
    <section>
      <h1 className="text-2xl font-bold">{title}</h1>
      <p className="mt-2 text-muted-foreground">{description}</p>
      <div className="mt-8">{children}</div>
    </section>
  )
}
