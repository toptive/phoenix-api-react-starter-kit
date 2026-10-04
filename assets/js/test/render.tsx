import { render } from "@testing-library/react"
import type { ReactElement } from "react"
import { I18nextProvider } from "react-i18next"

import en from "../../../i18n/locales/en.json"
import { createI18n } from "@/i18n"

/** Renders with the real English catalogue (i18n/locales/en.json). */
export function renderWithI18n(ui: ReactElement) {
  return render(<I18nextProvider i18n={createI18n("en", en)}>{ui}</I18nextProvider>)
}
