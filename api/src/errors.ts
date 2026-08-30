export const ERROR_STATUS = {
  method_not_allowed: 405,
  invalid_request: 400,
  invalid_safety_identifier: 400,
  unauthorized: 401,
  rate_limited: 429,
  model_unavailable: 503,
  invalid_model_output: 502,
  internal_error: 500,
} as const;

export type ErrorCode = keyof typeof ERROR_STATUS;

export class IntelligenceError extends Error {
  readonly code: ErrorCode;
  /** Safe to return to the client. Never contains trip content. */
  readonly detail?: string;

  constructor(code: ErrorCode, detail?: string) {
    super(code);
    this.name = "IntelligenceError";
    this.code = code;
    this.detail = detail;
  }
}

export function statusFor(code: ErrorCode): number {
  return ERROR_STATUS[code];
}
