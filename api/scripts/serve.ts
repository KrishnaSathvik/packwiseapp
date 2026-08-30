import { createServer } from "node:http";

import { gapsCapability } from "../src/capabilities/gaps.ts";
import { interpretCapability } from "../src/capabilities/interpret.ts";
import { optimizeCapability } from "../src/capabilities/optimize.ts";
import { IntelligenceError, statusFor } from "../src/errors.ts";
import { AppAttestIntegrityProvider } from "../src/integrity/provider.ts";
import { createHandler } from "../src/pipeline.ts";
import type { HttpRequest, HttpResponse } from "../src/pipeline.ts";
import { runtime } from "../src/runtime.ts";
import health from "../api/health.ts";

/**
 * A plain local server over the same handlers Vercel invokes. It exists so the
 * verification pass can run two instances against one Redis and prove that
 * state created by one is enforced by the other — the property serverless
 * depends on and the in-memory store can never demonstrate.
 *
 *   node --env-file=.env.local scripts/serve.ts 3000
 */
const port = Number(process.argv[2] ?? 3000);
const { config, store, adapter, integrity } = runtime();

const routes: Record<string, (req: HttpRequest, res: HttpResponse) => unknown> = {
  "/v1/trip/interpret": createHandler(interpretCapability, { config, store, adapter, integrity }),
  "/v1/packing/gaps": createHandler(gapsCapability, { config, store, adapter, integrity }),
  "/v1/packing/optimize": createHandler(optimizeCapability, { config, store, adapter, integrity }),
  "/health": health,
};

if (integrity instanceof AppAttestIntegrityProvider) {
  routes["/v1/integrity/challenge"] = async (request, response) => {
    if (request.method !== "POST") {
      response.status(405).json({ error: "method_not_allowed" });
      return;
    }
    response.status(200).json(await integrity.issueChallenge());
  };
  routes["/v1/integrity/attest"] = async (request, response) => {
    const body = request.body as { keyID?: string; attestation?: string; challenge?: string };
    if (!body?.keyID || !body.attestation || !body.challenge) {
      response.status(400).json({ error: "invalid_request" });
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
      // Mirror the Vercel route: the reason lives in `detail`, not `message`.
      const failure =
        error instanceof IntelligenceError ? error : new IntelligenceError("unauthorized");
      response.status(statusFor(failure.code)).json({
        error: failure.code,
        message: failure.detail,
      });
    }
  };
}

createServer((incoming, outgoing) => {
  const chunks: Buffer[] = [];
  incoming.on("data", (chunk: Buffer) => chunks.push(chunk));
  incoming.on("end", () => {
    const path = (incoming.url ?? "/").split("?")[0] ?? "/";
    const route = routes[path];
    if (!route) {
      outgoing.writeHead(404, { "Content-Type": "application/json" });
      outgoing.end(JSON.stringify({ error: "not_found", path }));
      return;
    }

    const raw = Buffer.concat(chunks).toString("utf8");
    const request: HttpRequest = {
      ...(incoming.method ? { method: incoming.method } : {}),
      headers: incoming.headers as Record<string, string | string[] | undefined>,
      body: raw.length > 0 ? JSON.parse(raw) : undefined,
    };

    let status = 200;
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    const response: HttpResponse = {
      status(code) {
        status = code;
        return response;
      },
      json(value) {
        outgoing.writeHead(status, headers);
        outgoing.end(JSON.stringify(value));
        return value;
      },
      setHeader(name, value) {
        headers[name] = String(value);
        return value;
      },
    };

    void Promise.resolve(route(request, response)).catch((error: unknown) => {
      outgoing.writeHead(500, { "Content-Type": "application/json" });
      outgoing.end(JSON.stringify({ error: "internal_error", message: String(error) }));
    });
  });
}).listen(port, () => {
  console.log(
    `PackWise API on :${port} — store ${store.kind}, adapter ${adapter.name}, integrity ${integrity.mode}`,
  );
});
