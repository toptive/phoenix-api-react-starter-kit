import { render } from "@testing-library/react"
import { I18nextProvider } from "react-i18next"
import type { ReactNode } from "react"
import { createI18n } from "@/i18n"
export function renderWithI18n(ui: ReactNode) {
  const i18n = createI18n("en")
  return render(ui, { wrapper: ({ children }) => <I18nextProvider i18n={i18n}>{children}</I18nextProvider> })
}
