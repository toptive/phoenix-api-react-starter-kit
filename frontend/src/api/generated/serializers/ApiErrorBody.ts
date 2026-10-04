export interface ApiErrorBody {
  code: string
  message: string
  details: Record<string, unknown>
}
