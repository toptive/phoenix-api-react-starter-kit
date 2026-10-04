export interface FieldError {
  key: string
  message: string
  bindings?: Record<string, string | number>
}
