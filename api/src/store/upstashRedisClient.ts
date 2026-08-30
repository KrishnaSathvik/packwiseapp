import { ProviderError } from "../model/errors.ts";
import type { RedisClient } from "./redisClient.ts";

/**
 * Upstash over its REST API, behind the same narrow interface as the TCP and
 * fake clients.
 *
 * REST is the better fit for serverless than a pooled TCP connection: each call
 * is a stateless HTTPS request, so there is no connection to establish, keep
 * warm, or leak across invocations. Every request is bounded, and there is no
 * fallback — an unreachable store throws so callers fail closed.
 */
const DEFAULT_TIMEOUT_MS = 3_000;

export class UpstashRedisClient implements RedisClient {
  private readonly baseURL: string;
  private readonly token: string;
  private readonly timeoutMs: number;

  constructor(baseURL: string, token: string, timeoutMs: number = DEFAULT_TIMEOUT_MS) {
    this.baseURL = baseURL.replace(/\/+$/, "");
    this.token = token;
    this.timeoutMs = timeoutMs;
  }

  /** Upstash takes a command as a JSON array and answers `{ result }`. */
  private async command<T>(...parts: (string | number)[]): Promise<T> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);

    let response: Response;
    try {
      response = await fetch(this.baseURL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${this.token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(parts.map(String)),
        signal: controller.signal,
      });
    } catch (error) {
      const aborted = controller.signal.aborted;
      throw new ProviderError(aborted ? "timeout" : "network", {
        message: `redis ${String(parts[0])} ${aborted ? "timed out" : "unreachable"}`,
      });
    } finally {
      clearTimeout(timer);
    }

    if (!response.ok) {
      // Status only. The body can echo the command, which may carry a key name.
      throw new ProviderError(response.status === 401 || response.status === 403 ? "auth" : "server", {
        status: response.status,
        message: `redis ${String(parts[0])} failed with ${response.status}`,
      });
    }

    const body = (await response.json()) as { result?: T; error?: string };
    if (body.error !== undefined) {
      throw new ProviderError("server", { message: `redis ${String(parts[0])} rejected` });
    }
    return body.result as T;
  }

  async get(key: string): Promise<string | null> {
    return (await this.command<string | null>("GET", key)) ?? null;
  }

  async set(
    key: string,
    value: string,
    options: { pxMs?: number; nx?: boolean } = {},
  ): Promise<boolean> {
    const parts: (string | number)[] = ["SET", key, value];
    if (options.pxMs !== undefined) parts.push("PX", options.pxMs);
    if (options.nx === true) parts.push("NX");
    // Upstash answers null when NX was requested and the key already existed.
    return (await this.command<string | null>(...parts)) !== null;
  }

  async del(key: string): Promise<number> {
    return this.command<number>("DEL", key);
  }

  async getdel(key: string): Promise<string | null> {
    return (await this.command<string | null>("GETDEL", key)) ?? null;
  }

  async incr(key: string): Promise<number> {
    return this.command<number>("INCR", key);
  }

  async pttl(key: string): Promise<number> {
    return this.command<number>("PTTL", key);
  }

  async pexpire(key: string, ms: number): Promise<boolean> {
    return (await this.command<number>("PEXPIRE", key, ms)) === 1;
  }

  async ping(): Promise<void> {
    await this.command<string>("PING");
  }
}
