import { randomBytes } from "node:crypto";

import type { Config } from "../config.ts";
import { IntelligenceError } from "../errors.ts";
import type { DurableStore } from "../store/durableStore.ts";
import { AttestationError, verifyAssertion, verifyAttestation } from "./appAttest.ts";
import type { VerifierOptions } from "./appAttest.ts";

export const CHALLENGE_TTL_MS = 5 * 60_000;

export type IntegrityResult = {
  /** Stable per-install identity used to scope rate limits. Not a person. */
  clientID: string;
  method: "development" | "appattest";
};

export type IntegrityRequest = {
  header(name: string): string | undefined;
  /** The parsed request body, re-serialized to check the assertion signature. */
  body?: unknown;
  requestID: string;
};

export interface AppIntegrityProvider {
  readonly mode: IntegrityResult["method"];
  verify(request: IntegrityRequest): Promise<IntegrityResult>;
}

/** Accepts any caller. Local development and tests only, selected explicitly. */
export class DevelopmentAppIntegrityProvider implements AppIntegrityProvider {
  readonly mode = "development" as const;

  async verify(request: IntegrityRequest): Promise<IntegrityResult> {
    const assertion = request.header("x-packwise-assertion");
    return {
      clientID: assertion && assertion.length > 0 ? `dev:${assertion.slice(0, 64)}` : "dev:anonymous",
      method: "development",
    };
  }
}

/**
 * Enforces a Secure Enclave assertion on every intelligence request.
 *
 * Registration happens once via `/v1/integrity/challenge` and
 * `/v1/integrity/attest`; after that each request carries an assertion over its
 * own body with a strictly increasing counter, so neither a stolen assertion
 * nor a replayed one is usable.
 */
export class AppAttestIntegrityProvider implements AppIntegrityProvider {
  readonly mode = "appattest" as const;

  private readonly store: DurableStore;
  private readonly options: VerifierOptions;
  private readonly now: () => number;

  constructor(store: DurableStore, options: VerifierOptions, now: () => number = Date.now) {
    this.store = store;
    this.options = options;
    this.now = now;
  }

  /** Issues a one-time challenge. Consumed on use, expired otherwise. */
  async issueChallenge(): Promise<{ challenge: string; expiresAt: string }> {
    const challenge = randomBytes(32).toString("base64url");
    await this.store.putChallenge(challenge, CHALLENGE_TTL_MS);
    return {
      challenge,
      expiresAt: new Date(this.now() + CHALLENGE_TTL_MS).toISOString(),
    };
  }

  async register(input: { keyID: string; attestation: string; challenge: string }): Promise<void> {
    // Consume first: a replayed or expired challenge never reaches the crypto.
    if (!(await this.store.consumeChallenge(input.challenge))) {
      throw new IntelligenceError("unauthorized", "challenge_invalid_or_used");
    }

    let result;
    try {
      result = verifyAttestation(input, this.options);
    } catch (error) {
      throw new IntelligenceError(
        "unauthorized",
        error instanceof AttestationError ? error.reason : "attestation_invalid",
      );
    }

    const at = this.now();
    await this.store.putKeyRecord({
      keyID: result.keyID,
      publicKey: result.publicKey,
      environment: result.environment,
      lastCounter: result.counter,
      createdAt: at,
      lastSeenAt: at,
    });
  }

  async verify(request: IntegrityRequest): Promise<IntegrityResult> {
    const keyID = request.header("x-packwise-key-id");
    const assertion = request.header("x-packwise-assertion");
    if (!keyID || !assertion) {
      throw new IntelligenceError("unauthorized", "assertion_missing");
    }

    const record = await this.store.getKeyRecord(keyID);
    if (!record) throw new IntelligenceError("unauthorized", "unknown_key");

    let result;
    try {
      result = verifyAssertion(
        {
          assertion,
          clientData: Buffer.from(canonicalBody(request.body), "utf8"),
          publicKey: record.publicKey,
        },
        this.options,
      );
    } catch (error) {
      throw new IntelligenceError(
        "unauthorized",
        error instanceof AttestationError ? error.reason : "assertion_invalid",
      );
    }

    // A counter that does not strictly increase is a replay.
    if (!(await this.store.advanceCounter(keyID, result.counter, this.now()))) {
      throw new IntelligenceError("unauthorized", "counter_replay");
    }

    return { clientID: `attested:${keyID}`, method: "appattest" };
  }
}

/**
 * The bytes the client signed. Both sides serialize the parsed body the same
 * way so the digest covers the request content rather than its formatting.
 */
export function canonicalBody(body: unknown): string {
  if (typeof body === "string") return body;
  return JSON.stringify(body ?? {});
}

export function integrityProviderFor(config: Config, store: DurableStore): AppIntegrityProvider {
  if (config.integrityMode !== "appattest") {
    return new DevelopmentAppIntegrityProvider();
  }
  // Never silently downgrade: refusing is the safe failure. The environment in
  // particular must be stated, because a sandbox key accepted as a production
  // one would defeat the whole check.
  if (!config.appleAppID || !config.appAttestEnvironment || !config.appAttestRootPEM) {
    throw new Error(
      "PACKWISE_APP_ID, PACKWISE_APP_ATTEST_ENVIRONMENT, and PACKWISE_APP_ATTEST_ROOT_PEM are required when PACKWISE_INTEGRITY_MODE=appattest",
    );
  }
  return new AppAttestIntegrityProvider(store, {
    appID: config.appleAppID,
    environment: config.appAttestEnvironment,
    rootCertificatePEM: config.appAttestRootPEM,
  });
}
