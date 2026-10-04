import { ArrowLeftIcon } from "lucide-react"
import { type ReactNode, useRef, useState } from "react"
import { useTranslation } from "react-i18next"

import { Button } from "@/components/ui/button"
import { Progress } from "@/components/ui/progress"

export type Step = {
  title: string
  description?: string
  /** Returns true when the step can move on (client-side check only; the server validates). */
  isValid?: () => boolean
  /** Shown (as an alert) when `isValid` refuses; says what to fix. */
  validationMessage?: string
  /** An optional step: a quiet "add this later" link next to the primary button. */
  skipLabel?: string
  /** Runs before a skip moves on (clear the field there). */
  onSkip?: () => void
  content: ReactNode
}

/**
 * Multi-step form: one question per step, progress, back navigation, and a final
 * review step. The default for anything with more than a few fields.
 *
 * The parent owns the react-hook-form data; this component only moves between steps.
 * The last step's primary button calls `onSubmit`. `reviewLastStep` marks the last step
 * as the review: progress counts only the questions. Pass `stepIndex` + `onStepChange`
 * to control the step from outside (reopen a half-finished form, save each step).
 * Moving to a step focuses its heading, so screen readers announce the new question.
 */
export function FormStepper({
  steps,
  onSubmit,
  submitLabel,
  processing,
  reviewLastStep = false,
  stepIndex,
  onStepChange,
}: {
  steps: Step[]
  onSubmit: () => void
  submitLabel: string
  processing?: boolean
  reviewLastStep?: boolean
  stepIndex?: number
  onStepChange?: (index: number) => void
}) {
  const { t } = useTranslation()
  const [internalIndex, setInternalIndex] = useState(0)
  const [invalidStep, setInvalidStep] = useState<number | null>(null)
  const index = stepIndex ?? internalIndex
  // The step whose heading was last shown: focus moves only on a change, never on page load.
  const shownIndex = useRef(index)
  const step = steps[index]
  if (!step) return null
  const last = index === steps.length - 1
  const reviewing = reviewLastStep && last
  const total = steps.length - (reviewLastStep ? 1 : 0)

  const moveTo = (next: number) => {
    setInvalidStep(null)
    setInternalIndex(next)
    onStepChange?.(next)
  }

  const focusHeading = (heading: HTMLHeadingElement | null) => {
    if (heading && shownIndex.current !== index) {
      shownIndex.current = index
      heading.focus()
    }
  }

  return (
    <form
      noValidate
      onSubmit={(event) => {
        event.preventDefault()
        if (processing) return
        if (step.isValid && !step.isValid()) {
          setInvalidStep(index)
          return
        }
        if (last) onSubmit()
        else moveTo(index + 1)
      }}
      className="space-y-6"
    >
      <div className="space-y-2">
        <p className="text-sm text-muted-foreground">{reviewing ? t("stepper.review") : t("stepper.progress", { current: index + 1, total })}</p>
        <Progress value={Math.min(100, ((index + 1) / total) * 100)} aria-hidden="true" />
      </div>
      <div className="space-y-1">
        <h2 key={index} ref={focusHeading} tabIndex={-1} className="text-xl font-semibold focus:outline-none">
          {step.title}
        </h2>
        {step.description && <p className="text-muted-foreground">{step.description}</p>}
      </div>
      <fieldset disabled={processing} className="min-w-0 space-y-4">
        {step.content}
      </fieldset>
      {invalidStep === index && step.isValid?.() === false && (
        <p role="alert" className="text-sm text-destructive">
          {step.validationMessage ?? t("stepper.invalid")}
        </p>
      )}
      <div className="flex flex-wrap items-center justify-between gap-3">
        {index > 0 ? (
          <Button type="button" variant="ghost" onClick={() => moveTo(index - 1)} disabled={processing}>
            <ArrowLeftIcon /> {t("stepper.back")}
          </Button>
        ) : (
          <span />
        )}
        <div className="flex flex-wrap items-center gap-3">
          {step.skipLabel && !last && (
            <Button
              type="button"
              variant="link"
              className="text-muted-foreground"
              disabled={processing}
              onClick={() => {
                step.onSkip?.()
                moveTo(index + 1)
              }}
            >
              {step.skipLabel}
            </Button>
          )}
          <Button type="submit" disabled={processing}>
            {last ? submitLabel : t("stepper.next")}
          </Button>
        </div>
      </div>
    </form>
  )
}
