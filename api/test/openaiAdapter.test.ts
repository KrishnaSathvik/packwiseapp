import assert from "node:assert/strict";
import test from "node:test";

import { manifest, modelOutputSchema } from "../src/generated.ts";
import { OpenAIResponsesModelAdapter } from "../src/model/openai/adapter.ts";
import type { OpenAIRequestBody, OpenAIResponseBody, OpenAITransport } from "../src/model/openai/transport.ts";
import { ProviderError } from "../src/model/errors.ts";
import { PROMPTS } from "../src/prompts/index.ts";
import { CAPABILITY_CONFIG } from "../src/versions.ts";
import type { ModelRequest } from "../src/model/adapter.ts";

/**
 * The live adapter without a key. Everything about the outbound request is
 * provable here; whether OpenAI accepts it is the live smoke pass.
 */
class StubOpenAITransport implements OpenAITransport {
  sent: OpenAIRequestBody[] = [];
  apiKeys: string[] = [];
  response: OpenAIResponseBody = { id: "resp_1", output_text: "{}" };
  failure?: Error;

  async send(options: {
    body: OpenAIRequestBody;
    apiKey: string;
  }): Promise<OpenAIResponseBody> {
    this.sent.push(options.body);
    this.apiKeys.push(options.apiKey);
    if (this.failure) throw this.failure;
    return this.response;
  }
}

function request(overrides: Partial<ModelRequest> = {}): ModelRequest {
  return {
    capability: "gaps",
    model: "gpt-5.6",
    promptVersion: "gaps/1",
    input: { trip: { destination: "Tokyo" }, presentItemIDs: [] },
    safetyIdentifier: "hmac-derived-opaque-value",
    requestID: "req-1",
    signal: new AbortController().signal,
    ...overrides,
  };
}

function adapter(transport: StubOpenAITransport) {
  return new OpenAIResponsesModelAdapter({ apiKey: "sk-test", transport });
}

test("the Structured Outputs schema is the generated one, not a second copy", () => {
  const transport = new StubOpenAITransport();
  const body = adapter(transport).buildRequest(request());

  assert.equal(body.text.format.type, "json_schema");
  assert.equal(body.text.format.strict, true);
  assert.equal(body.text.format.name, manifest().capabilities.gaps?.definition);
  assert.deepEqual(body.text.format.schema, modelOutputSchema("gaps"));
});

test("store is explicitly false", () => {
  const body = adapter(new StubOpenAITransport()).buildRequest(request());
  assert.equal(body.store, false);
});

test("the safety identifier is passed through and is not the raw install token", () => {
  const body = adapter(new StubOpenAITransport()).buildRequest(
    request({ safetyIdentifier: "hmac-derived-opaque-value" }),
  );
  assert.equal(body.safety_identifier, "hmac-derived-opaque-value");
});

test("the model comes from the request, never a literal", () => {
  const body = adapter(new StubOpenAITransport()).buildRequest(request({ model: "gpt-5.6-terra" }));
  assert.equal(body.model, "gpt-5.6-terra");
});

test("each capability sends its own versioned prompt", () => {
  const built = adapter(new StubOpenAITransport());
  for (const capability of ["interpret", "gaps", "optimize"] as const) {
    const body = built.buildRequest(request({ capability }));
    assert.equal(body.input[0]?.role, "system");
    assert.equal(body.input[0]?.content, PROMPTS[capability].system);
    assert.equal(body.input[1]?.role, "user");
  }
});

test("prompt versions match the capability configuration", () => {
  for (const capability of ["interpret", "gaps", "optimize"] as const) {
    assert.equal(PROMPTS[capability].version, CAPABILITY_CONFIG[capability].promptVersion);
  }
});

test("prompts state the boundaries the schema cannot express", () => {
  for (const capability of ["interpret", "gaps", "optimize"] as const) {
    const system = PROMPTS[capability].system;
    assert.match(system, /Do not invent canonical item IDs/);
    assert.match(system, /Do not make packing quantity decisions/);
    assert.match(system, /Do not override or contradict explicit user choices/);
    // The Reykjavik fixture is exactly this distinction.
    assert.match(system, /fact about the place/);
  }
});

test("provider metadata is parsed for server-side tracing", async () => {
  const transport = new StubOpenAITransport();
  transport.response = {
    id: "resp_abc",
    output_text: JSON.stringify({ suggestions: [] }),
    usage: { input_tokens: 812, output_tokens: 44 },
  };

  const result = await adapter(transport).produce(request());
  assert.deepEqual(result.output, { suggestions: [] });
  assert.equal(result.providerResponseID, "resp_abc");
  assert.equal(result.inputTokens, 812);
  assert.equal(result.outputTokens, 44);
});

test("output is read from the content parts when output_text is absent", async () => {
  const transport = new StubOpenAITransport();
  transport.response = {
    id: "resp_def",
    output: [{ content: [{ type: "output_text", text: JSON.stringify({ suggestions: [] }) }] }],
  };
  const result = await adapter(transport).produce(request());
  assert.deepEqual(result.output, { suggestions: [] });
});

test("a response that is not JSON is a provider failure, not a silent empty result", async () => {
  const transport = new StubOpenAITransport();
  transport.response = { id: "resp_ghi", output_text: "I'd suggest a power bank!" };

  await assert.rejects(
    () => adapter(transport).produce(request()),
    (error: unknown) => error instanceof ProviderError && error.kind === "malformed",
  );
});

test("the API key is sent to the transport and never appears in the body", async () => {
  const transport = new StubOpenAITransport();
  transport.response = { output_text: "{}" };
  await adapter(transport).produce(request());

  assert.deepEqual(transport.apiKeys, ["sk-test"]);
  assert.ok(!JSON.stringify(transport.sent[0]).includes("sk-test"));
});
