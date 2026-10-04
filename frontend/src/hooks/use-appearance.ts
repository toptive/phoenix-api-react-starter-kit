import { useCallback, useSyncExternalStore } from "react"

import { storageKey } from "@/lib/storage-keys"

export type Appearance = "light" | "dark" | "system"

const STORAGE_KEY = storageKey("appearance")
const listeners = new Set<() => void>()

function prefersDark(): boolean {
  return window.matchMedia("(prefers-color-scheme: dark)").matches
}

/** The stored choice ("system" when none). */
export function readAppearance(): Appearance {
  if (typeof window === "undefined") return "system"
  const value = window.localStorage.getItem(STORAGE_KEY)
  return value === "light" || value === "dark" ? value : "system"
}

/** Applies the class on <html>. The inline script in index.html does the same before first paint. */
export function applyAppearance(appearance: Appearance) {
  const dark = appearance === "dark" || (appearance === "system" && prefersDark())
  document.documentElement.classList.toggle("dark", dark)
  document.documentElement.style.colorScheme = dark ? "dark" : "light"
}

function subscribe(listener: () => void) {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function useAppearance() {
  const appearance = useSyncExternalStore(subscribe, readAppearance, () => "system" as Appearance)

  const setAppearance = useCallback((value: Appearance) => {
    if (value === "system") window.localStorage.removeItem(STORAGE_KEY)
    else window.localStorage.setItem(STORAGE_KEY, value)
    applyAppearance(value)
    listeners.forEach((listener) => listener())
  }, [])

  return { appearance, setAppearance } as const
}
