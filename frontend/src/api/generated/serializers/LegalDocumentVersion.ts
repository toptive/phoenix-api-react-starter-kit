export interface LegalDocumentVersion {
  id: string
  number: number
  note: string | null
  publishedAt: string | null
  insertedAt: string
  titles: Record<string, string>
  bodies: Record<string, string>
}
