import { createClient } from "redis";
import type { RedisClientType } from "redis";

import type { RedisClient } from "./redisClient.ts";

/**
 * The real client, behind the same narrow interface `FakeRedisClient`
 * implements. Swapping providers — Upstash, Redis Cloud — is a URL change;
 * swapping transports (say to Upstash's REST API, if serverless connection
 * churn ever demands it) is this one file.
 *
 * Connection is lazy and shared, so a warm serverless instance reuses it.
 * There is no fallback: if Redis is unreachable the operation throws, and the
 * caller fails closed rather than degrading to process memory.
 */
const CONNECT_TIMEOUT_MS = 3_000;
const OPERATION_TIMEOUT_MS = 3_000;
const MAX_RECONNECT_ATTEMPTS = 2;

export class RealRedisClient implements RedisClient {
  private readonly client: RedisClientType;
  private connection?: Promise<void>;

  constructor(url: string, timeoutMs: number = OPERATION_TIMEOUT_MS) {
    this.timeoutMs = timeoutMs;
    this.client = createClient({
      url,
      socket: {
        connectTimeout: CONNECT_TIMEOUT_MS,
        // Bounded on purpose. The default retries forever, which turns "fail
        // closed" into "hang forever" — every request stalls instead of
        // surfacing that the store is gone.
        reconnectStrategy: (retries) =>
          retries > MAX_RECONNECT_ATTEMPTS
            ? new Error("redis unreachable")
            : Math.min(100 * 2 ** retries, 1_000),
      },
    }) as RedisClientType;
    // Without a listener, a connection error becomes an unhandled rejection and
    // takes the process down instead of surfacing on the awaiting call.
    this.client.on("error", () => {});
  }

  private readonly timeoutMs: number;

  /**
   * Every operation is bounded. An unreachable store must produce an error
   * quickly, so callers fail closed rather than stalling.
   */
  private async withTimeout<T>(operation: Promise<T>, label: string): Promise<T> {
    let timer: NodeJS.Timeout | undefined;
    try {
      return await Promise.race([
        operation,
        new Promise<never>((_resolve, reject) => {
          timer = setTimeout(
            () => reject(new Error(`redis ${label} timed out after ${this.timeoutMs}ms`)),
            this.timeoutMs,
          );
        }),
      ]);
    } finally {
      if (timer) clearTimeout(timer);
    }
  }

  private async ready(): Promise<RedisClientType> {
    this.connection ??= this.withTimeout(
      this.client.connect().then(() => undefined),
      "connect",
    ).catch((error: unknown) => {
      // Let the next call retry rather than caching a permanent failure.
      this.connection = undefined;
      throw error;
    });
    await this.connection;
    return this.client;
  }

  async get(key: string): Promise<string | null> {
    const client = await this.ready();
    return this.withTimeout(client.get(key), "get");
  }

  async set(
    key: string,
    value: string,
    options: { pxMs?: number; nx?: boolean } = {},
  ): Promise<boolean> {
    const client = await this.ready();
    const result = await this.withTimeout(
      client.set(key, value, {
      ...(options.pxMs === undefined ? {} : { PX: options.pxMs }),
        ...(options.nx === true ? { NX: true } : {}),
      }),
      "set",
    );
    // node-redis returns null when NX was requested and the key existed.
    return result !== null;
  }

  async del(key: string): Promise<number> {
    const client = await this.ready();
    return this.withTimeout(client.del(key), "del");
  }

  async getdel(key: string): Promise<string | null> {
    const client = await this.ready();
    return this.withTimeout(client.getDel(key), "getdel");
  }

  async incr(key: string): Promise<number> {
    const client = await this.ready();
    return this.withTimeout(client.incr(key), "incr");
  }

  async pttl(key: string): Promise<number> {
    const client = await this.ready();
    return this.withTimeout(client.pTTL(key), "pttl");
  }

  async pexpire(key: string, ms: number): Promise<boolean> {
    const client = await this.ready();
    // node-redis reports 1/0 rather than a boolean here.
    return Boolean(await this.withTimeout(client.pExpire(key, ms), "pexpire"));
  }

  /** Fails loudly if Redis is unreachable, for `/health` and startup checks. */
  async ping(): Promise<void> {
    const client = await this.ready();
    await this.withTimeout(client.ping(), "ping");
  }

  async close(): Promise<void> {
    if (this.connection) await this.client.close();
  }
}
