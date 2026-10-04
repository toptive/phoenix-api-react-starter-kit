export interface AuditEvent {
  id: string
  action: string
  actorId: string | null
  impersonatorId: string | null
  organizationId: string | null
  subjectType: string | null
  subjectId: string | null
  metadata: Record<string, unknown>
  insertedAt: string
  actorEmail: string | null
}
