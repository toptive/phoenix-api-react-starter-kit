import { useMutation } from "@tanstack/react-query"
import { uploadFile, type UploadKind } from "../uploads"
export const useDirectUpload = (kind: UploadKind) =>
  useMutation({
    mutationKey: ["direct-upload", kind],
    mutationFn: (file: File) => uploadFile(file, kind),
  })
