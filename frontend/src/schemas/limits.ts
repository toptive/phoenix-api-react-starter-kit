/** Input limits shared by client validation and translated field messages. */
export const limits = {
  emailMax: 160,
  nameMax: 120,
  organizationMin: 2,
  organizationMax: 80,
  passwordMin: 12,
  passwordMaxBytes: 72,
} as const
