import { fireEvent, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import { FormStepper } from "@/components/app/form-stepper"
import { renderWithI18n } from "@/test/render"

describe("FormStepper", () => {
  it("moves forward, back, and submits on the last step", () => {
    const onSubmit = vi.fn()
    renderWithI18n(
      <FormStepper
        submitLabel="Send"
        onSubmit={onSubmit}
        steps={[
          { title: "Who?", content: <p>one</p> },
          { title: "Check", content: <p>two</p> },
        ]}
      />,
    )

    expect(screen.getByText("Step 1 of 2")).toBeTruthy()
    fireEvent.click(screen.getByRole("button", { name: "Continue" }))
    expect(screen.getByText("Check")).toBeTruthy()
    fireEvent.click(screen.getByRole("button", { name: "Back" }))
    expect(screen.getByText("Who?")).toBeTruthy()
    fireEvent.click(screen.getByRole("button", { name: "Continue" }))
    fireEvent.click(screen.getByRole("button", { name: "Send" }))
    expect(onSubmit).toHaveBeenCalledOnce()
  })

  it("stays on a step that is not valid and says why in an alert", () => {
    renderWithI18n(
      <FormStepper
        submitLabel="Send"
        onSubmit={vi.fn()}
        steps={[
          { title: "Email", isValid: () => false, validationMessage: "Write an email address.", content: null },
          { title: "Next", content: null },
        ]}
      />,
    )
    expect(screen.queryByRole("alert")).toBeNull()
    fireEvent.click(screen.getByRole("button", { name: "Continue" }))
    expect(screen.getByText("Email")).toBeTruthy()
    expect(screen.getByRole("alert").textContent).toBe("Write an email address.")
  })

  it("falls back to a generic message when the step has none", () => {
    renderWithI18n(<FormStepper submitLabel="Send" onSubmit={vi.fn()} steps={[{ title: "Email", isValid: () => false, content: null }]} />)
    fireEvent.click(screen.getByRole("button", { name: "Send" }))
    expect(screen.getByRole("alert").textContent).toBe("Check this answer before continuing.")
  })

  it("focuses the new heading on a step change, never on first render", () => {
    renderWithI18n(<FormStepper submitLabel="Send" onSubmit={vi.fn()} steps={[{ title: "Who?", content: null }, { title: "Check", content: null }]} />)
    expect(document.activeElement).not.toBe(screen.getByRole("heading", { name: "Who?" }))
    fireEvent.click(screen.getByRole("button", { name: "Continue" }))
    expect(document.activeElement).toBe(screen.getByRole("heading", { name: "Check" }))
    fireEvent.click(screen.getByRole("button", { name: "Back" }))
    expect(document.activeElement).toBe(screen.getByRole("heading", { name: "Who?" }))
  })

  it("counts only the questions when the last step is the review", () => {
    renderWithI18n(
      <FormStepper reviewLastStep submitLabel="Send" onSubmit={vi.fn()} steps={[{ title: "A", content: null }, { title: "B", content: null }, { title: "Review", content: null }]} />,
    )
    expect(screen.getByText("Step 1 of 2")).toBeTruthy()
    fireEvent.click(screen.getByRole("button", { name: "Continue" }))
    expect(screen.getByText("Step 2 of 2")).toBeTruthy()
    fireEvent.click(screen.getByRole("button", { name: "Continue" }))
    expect(screen.getByText("Review your answers")).toBeTruthy()
  })

  it("skips an optional step and runs its onSkip", () => {
    const onSkip = vi.fn()
    renderWithI18n(
      <FormStepper submitLabel="Send" onSubmit={vi.fn()} steps={[{ title: "Website", isValid: () => false, skipLabel: "Add it later", onSkip, content: null }, { title: "Done", content: null }]} />,
    )
    fireEvent.click(screen.getByRole("button", { name: "Add it later" }))
    expect(onSkip).toHaveBeenCalledOnce()
    expect(screen.getByText("Done")).toBeTruthy()
  })

  it("follows a controlled stepIndex and reports every move", () => {
    const onStepChange = vi.fn()
    renderWithI18n(
      <FormStepper stepIndex={1} onStepChange={onStepChange} submitLabel="Send" onSubmit={vi.fn()} steps={[{ title: "A", content: null }, { title: "B", content: null }, { title: "C", content: null }]} />,
    )
    expect(screen.getByText("B")).toBeTruthy()
    fireEvent.click(screen.getByRole("button", { name: "Continue" }))
    expect(onStepChange).toHaveBeenCalledWith(2)
  })

  it("locks the step while the form is sending", () => {
    const onSubmit = vi.fn()
    renderWithI18n(<FormStepper processing submitLabel="Send" onSubmit={onSubmit} steps={[{ title: "A", content: <input aria-label="Name" /> }]} />)
    expect(screen.getByRole("textbox", { name: "Name" }).matches(":disabled")).toBe(true)
    fireEvent.submit(screen.getByRole("button", { name: "Send" }).closest("form")!)
    expect(onSubmit).not.toHaveBeenCalled()
  })
})
