import { toast } from "sonner"

/** Shows the server flash (after a redirect) as a toast. */
export function showFlash(flash: Record<string, string> | undefined) {
  if (!flash) return
  if (flash.info) toast.success(flash.info)
  if (flash.error) toast.error(flash.error)
}
