import { useSyncExternalStore } from "react"
let status: number | null = null
const listeners = new Set<() => void>()
export function reportApiFailure(next: number) {
  if (![403, 404].includes(next) && next < 500) return
  status = next
  listeners.forEach((listener) => listener())
}
export function clearApiFailure() {
  status = null
  listeners.forEach((listener) => listener())
}
const subscribe = (listener: () => void) => {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}
export const useApiFailure = () =>
  useSyncExternalStore(
    subscribe,
    () => status,
    () => null,
  )
