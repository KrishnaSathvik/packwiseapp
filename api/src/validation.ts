// The 2020-12 build, because the generated schemas declare that dialect.
import { Ajv2020 } from "ajv/dist/2020.js";
import type { ValidateFunction } from "ajv";

import { apiSchema, manifest, modelOutputSchema } from "./generated.ts";
import { IntelligenceError } from "./errors.ts";

const API_SCHEMA_ID = "https://packwise.app/schemas/intelligence/api.schema.json";

const ajv = new Ajv2020({ strict: false, allErrors: true, allowUnionTypes: true });
ajv.addSchema(apiSchema(), API_SCHEMA_ID);
for (const capability of Object.keys(manifest().capabilities)) {
  ajv.addSchema(modelOutputSchema(capability), modelSchemaID(capability));
}

function modelSchemaID(capability: string): string {
  return `https://packwise.app/schemas/intelligence/model-output/${capability}.schema.json`;
}

const cache = new Map<string, ValidateFunction>();

function validator(ref: string): ValidateFunction {
  const cached = cache.get(ref);
  if (cached) return cached;
  const compiled = ajv.compile({ $ref: ref });
  cache.set(ref, compiled);
  return compiled;
}

/**
 * Error text is derived from schema paths only. Instance values are never
 * echoed, so a validation failure can't leak trip content into logs.
 */
function describe(validate: ValidateFunction): string {
  return (validate.errors ?? [])
    .slice(0, 5)
    .map((error) => `${error.instancePath || "/"} ${error.message ?? "invalid"}`)
    .join("; ");
}

export function validateRequest<T>(definition: string, body: unknown): T {
  const validate = validator(`${API_SCHEMA_ID}#/$defs/${definition}`);
  if (!validate(body)) {
    throw new IntelligenceError("invalid_request", describe(validate));
  }
  return body as T;
}

/** Responses are validated on the way out too. A malformed response is a bug we own. */
export function validateResponse<T>(definition: string, body: T): T {
  const validate = validator(`${API_SCHEMA_ID}#/$defs/${definition}`);
  if (!validate(body)) {
    throw new IntelligenceError("internal_error", `response ${definition}: ${describe(validate)}`);
  }
  return body;
}

/** Validates against the same generated schema the model was handed. */
export function validateModelOutput<T>(capability: string, body: unknown): T {
  const validate = validator(modelSchemaID(capability));
  if (!validate(body)) {
    throw new IntelligenceError("invalid_model_output", describe(validate));
  }
  return body as T;
}

/**
 * A privacy-preserving stable identifier: opaque, never an email, device ID, or
 * anything else that identifies a person.
 */
const SAFETY_IDENTIFIER = /^[A-Za-z0-9_-]{8,128}$/;

export function assertSafetyIdentifier(value: string): void {
  if (!SAFETY_IDENTIFIER.test(value)) {
    throw new IntelligenceError(
      "invalid_safety_identifier",
      "safetyIdentifier must be an opaque token of 8-128 URL-safe characters",
    );
  }
}
