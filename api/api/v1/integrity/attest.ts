import { randomUUID } from "node:crypto";

import { IntelligenceError, statusFor } from "../../../src/errors.ts";
import { AppAttestIntegrityProvider } from "../../../src/integrity/provider.ts";
import { runtime } from "../../../src/runtime.ts";
import type { HttpRequest, HttpResponse } from "../../../src/pipeline.ts";

/** Registers an attestation, binding a Secure Enclave key to this install. */
export default async function handler(request: HttpRequest, response: HttpResponse): Promise<void> {
  const requestID = randomUUID();
  response.setHeader("X-Request-ID", requestID);

  if (request.method !== "POST") {
    response.status(405).json({ error: "method_not_allowed", requestID });
    return;
  }

  const { integrity } = runtime();
  if (!(integrity instanceof AppAttestIntegrityProvider)) {
    response.status(404).json({
      error: "not_found",
      message: "App Attest is not enabled in this environment",
      requestID,
    });
    return;
  }

  const body = (typeof request.body === "string" ? JSON.parse(request.body) : request.body) as {
    keyID?: string;
    attestation?: string;
    challenge?: string;
  };

  if (!body?.keyID || !body.attestation || !body.challenge) {
    response.status(400).json({ error: "invalid_request", requestID });
    return;
  }

  try {
    await integrity.register({
      keyID: body.keyID,
      attestation: body.attestation,
      challenge: body.challenge,
    });
    response.status(204).json({});
  } catch (error) {
    const failure =
      error instanceof IntelligenceError ? error : new IntelligenceError("unauthorized");
    response.status(statusFor(failure.code)).json({
      error: failure.code,
      message: failure.detail,
      requestID,
    });
  }
}
