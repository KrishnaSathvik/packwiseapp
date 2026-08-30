/**
 * Why a provider call failed, in the only terms the retry policy cares about.
 * Classifying at the transport boundary keeps the policy free of HTTP details.
 */
export type ProviderFailureKind =
  /** Connection reset, DNS, TLS. Worth one retry. */
  | "network"
  /** Request took longer than the capability budget. Worth one retry. */
  | "timeout"
  /** 429. Worth a bounded retry with jitter. */
  | "rate_limited"
  /** Retryable 5xx. */
  | "server"
  /** 400-class: our request is wrong. Retrying sends the same wrong request. */
  | "client"
  /** 401/403. Retrying cannot fix credentials. */
  | "auth"
  /** Provider returned something we could not parse as the agreed shape. */
  | "malformed";

const RETRYABLE = new Set<ProviderFailureKind>(["network", "timeout", "rate_limited", "server"]);

export class ProviderError extends Error {
  readonly kind: ProviderFailureKind;
  readonly status?: number;
  /** Seconds the provider asked us to wait, when it said. */
  readonly retryAfterSeconds?: number;

  constructor(
    kind: ProviderFailureKind,
    options: { status?: number; retryAfterSeconds?: number; message?: string } = {},
  ) {
    super(options.message ?? kind);
    this.name = "ProviderError";
    this.kind = kind;
    if (options.status !== undefined) this.status = options.status;
    if (options.retryAfterSeconds !== undefined) this.retryAfterSeconds = options.retryAfterSeconds;
  }

  get isRetryable(): boolean {
    return RETRYABLE.has(this.kind);
  }
}

export function providerErrorForStatus(status: number, retryAfterSeconds?: number): ProviderError {
  const options = retryAfterSeconds === undefined ? { status } : { status, retryAfterSeconds };
  if (status === 429) return new ProviderError("rate_limited", options);
  if (status === 401 || status === 403) return new ProviderError("auth", options);
  if (status >= 500) return new ProviderError("server", options);
  return new ProviderError("client", options);
}
