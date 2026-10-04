import type { LegalDocumentVersion } from "./LegalDocumentVersion"
export interface LegalDocument {
  id: string
  slug: string
  publishedVersionId: string | null
  versions: LegalDocumentVersion[]
}
