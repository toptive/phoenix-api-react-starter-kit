import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import { LegalBody } from "@/components/app/legal-body"

describe("LegalBody", () => {
  it("renders headings and paragraphs and never injects HTML", () => {
    render(<LegalBody body={"## Scope\n\nFirst <b>paragraph</b>.\n\nSecond."} />)
    expect(screen.getByRole("heading", { name: "Scope" })).toBeTruthy()
    expect(screen.getByText("First <b>paragraph</b>.")).toBeTruthy()
    expect(document.querySelector("b")).toBeNull()
  })
})
