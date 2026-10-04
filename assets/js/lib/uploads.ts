import type { DirectUpload } from "@/generated/serializers"
import { routes } from "@/generated/routes"

export type UploadKind = "image" | "document" | "avatar"

export class UploadError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message)
  }
}

/**
 * Direct upload to object storage (StarterKit.Uploads): the server signs, the browser
 * PUTs the file straight to storage, and the returned key goes into the Inertia form.
 * The one place allowed to call fetch (uploads are not page data).
 *
 *   const key = await uploadFile(file, "image")
 *   form.setData("photoKey", key)
 */
export async function uploadFile(file: File, kind: UploadKind): Promise<string> {
  const csrf = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""
  const signed = await fetch(routes.apiV1DirectUpload.create().url, {
    method: "POST",
    headers: { "content-type": "application/json", accept: "application/json", "x-csrf-token": csrf },
    body: JSON.stringify({ directUpload: { filename: file.name, contentType: file.type, byteSize: file.size, kind } }),
  })
  const body = (await signed.json()) as { data?: DirectUpload; error?: { code: string; message: string } }
  if (!signed.ok || !body.data) throw new UploadError(body.error?.code ?? "upload_failed", body.error?.message ?? "")

  const put = await fetch(body.data.url, { method: body.data.method, headers: body.data.headers, body: file })
  if (!put.ok) throw new UploadError("storage_rejected", put.statusText)
  return body.data.key
}
