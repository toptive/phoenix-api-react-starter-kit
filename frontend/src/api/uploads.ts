import type { DirectUpload } from "./generated/serializers"
import { apiV1DirectUploads } from "./generated/routes"
import { api, ApiError } from "./http"

export type UploadKind = "image" | "document" | "avatar"
export class UploadError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message)
  }
}
/** The API signs the upload; only the file PUT goes directly to object storage. */
export async function uploadFile(file: File, kind: UploadKind): Promise<string> {
  let upload: DirectUpload
  try {
    upload = (
      await api.post<DirectUpload>(apiV1DirectUploads.create(), {
        filename: file.name,
        contentType: file.type,
        byteSize: file.size,
        kind,
      })
    ).data
  } catch (error) {
    if (error instanceof ApiError) throw new UploadError(error.code, error.message)
    throw error
  }
  const put = await fetch(upload.url, { method: upload.method, headers: upload.headers, body: file })
  if (!put.ok) throw new UploadError("storage_rejected", put.statusText)
  return upload.key
}
