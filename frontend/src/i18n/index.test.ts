import { describe, expect, it } from "vitest"

import { applyTranslations, createI18n } from "@/i18n"

describe("i18n", () => {
  it("uses flat keys and {{placeholders}}, and switches catalogue", () => {
    const i18n = createI18n("en", { "dashboard.greeting": "Hi, {{name}}" })
    expect(i18n.t("dashboard.greeting", { name: "Ana" })).toBe("Hi, Ana")

    applyTranslations(i18n, "es", { "dashboard.greeting": "Hola, {{name}}" })
    expect(i18n.language).toBe("es")
    expect(i18n.t("dashboard.greeting", { name: "Ana" })).toBe("Hola, Ana")
  })
})
