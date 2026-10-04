import { createContext, useContext, useCallback } from "react"
import { withSudoConfirmation } from "@/lib/sudo"

export const SudoContext = createContext<(() => Promise<void>) | null>(null)
export function useSudoAction() {
  const confirm = useContext(SudoContext)
  return useCallback(
    <T>(action: () => Promise<T>) => {
      if (!confirm) throw new Error("SudoProvider is missing")
      return withSudoConfirmation(action, confirm)
    },
    [confirm],
  )
}
