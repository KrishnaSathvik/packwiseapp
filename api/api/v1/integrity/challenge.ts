import { randomUUID } from "node:crypto";

import { AppAttestIntegrityProvider } from "../../../src/integrity/provider.ts";
import { runtime } from "../../../src/runtime.ts";
import type { HttpRequest, HttpResponse } from "../../../src/pipeline.ts";

/** Issues the one-time challenge an attestation must be bound to. */
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

  response.status(200).json(await integrity.issueChallenge());
}
