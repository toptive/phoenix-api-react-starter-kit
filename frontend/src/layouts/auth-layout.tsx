import type { ReactNode } from "react"

import { LocaleSwitcher } from "@/components/app/locale-switcher"
import { Logo } from "@/components/app/logo"

/** Sign up, sign in, magic link and invitation pages: one calm column. */
export function AuthLayout({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-full flex-col">
      <header className="mx-auto flex h-16 w-full max-w-5xl items-center justify-between px-4 sm:px-6">
        <Logo />
        <LocaleSwitcher />
      </header>
      <main id="main" className="flex flex-1 items-start justify-center px-4 pb-16 pt-6 sm:pt-16">
        <div className="w-full max-w-md">{children}</div>
      </main>
    </div>
  )
}
