import type { Pagination } from "./Pagination"
export interface Envelope<T> {
  data: T
  meta?: { pagination?: Pagination; [k: string]: unknown }
}
