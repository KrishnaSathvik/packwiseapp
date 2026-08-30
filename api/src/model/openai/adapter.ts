import { manifest, modelOutputSchema } from "../../generated.ts";
import { PROMPTS } from "../../prompts/index.ts";
import type { ModelAdapter, ModelRequest, ModelResult } from "../adapter.ts";
import { ProviderError } from "../errors.ts";
import { FetchOpenAITransport } from "./transport.ts";
import type { OpenAIRequestBody, OpenAITransport } from "./transport.ts";

/**
 * The live adapter. Same seam as `FakeModelAdapter`, so nothing above it
 * changes when this is selected.
 *
 * The Structured Outputs schema is the **generated**
 * `api/generated/schemas/model-output/<capability>.schema.json` — the same file
 * the response is then validated against. There is no second, hand-written copy
 * that could drift from what we enforce.
 */
export class OpenAIResponsesModelAdapter implements ModelAdapter {
  readonly name = "openai-responses";

  private readonly apiKey: string;
  private readonly baseURL: string;
  private readonly transport: OpenAITransport;

  constructor(options: {
    apiKey: string;
    baseURL?: string;
    transport?: OpenAITransport;
  }) {
    this.apiKey = options.apiKey;
    this.baseURL = options.baseURL ?? "https://api.openai.com/v1";
    this.transport = options.transport ?? new FetchOpenAITransport();
  }

  buildRequest(request: ModelRequest): OpenAIRequestBody {
    const prompt = PROMPTS[request.capability];
    const entry = manifest().capabilities[request.capability];
    if (!entry) throw new Error(`no generated schema for capability ${request.capability}`);

    return {
      model: request.model,
      input: [
        { role: "system", content: prompt.system },
        { role: "user", content: prompt.user(request.input) },
      ],
      text: {
        format: {
          type: "json_schema",
          name: entry.definition,
          strict: true,
          schema: modelOutputSchema(request.capability),
        },
      },
      // PackWise does not want trip content retained by the provider.
      store: false,
      // Already HMAC'd by the pipeline: opaque, stable, not a person.
      safety_identifier: request.safetyIdentifier,
    };
  }

  async produce(request: ModelRequest): Promise<ModelResult> {
    const body = await this.transport.send({
      body: this.buildRequest(request),
      apiKey: this.apiKey,
      baseURL: this.baseURL,
      requestID: request.requestID,
      signal: request.signal,
    });

    const text = extractText(body);
    if (text === undefined) {
      throw new ProviderError("malformed", { message: "no output text in response" });
    }

    let output: unknown;
    try {
      output = JSON.parse(text);
    } catch {
      throw new ProviderError("malformed", { message: "output text was not JSON" });
    }

    const result: ModelResult = { output };
    if (body.id !== undefined) result.providerResponseID = body.id;
    if (body.usage?.input_tokens !== undefined) result.inputTokens = body.usage.input_tokens;
    if (body.usage?.output_tokens !== undefined) result.outputTokens = body.usage.output_tokens;
    return result;
  }
}

/** `output_text` when the provider offers it, otherwise the first text part. */
function extractText(body: {
  output_text?: string;
  output?: { content?: { type?: string; text?: string }[] }[];
}): string | undefined {
  if (typeof body.output_text === "string" && body.output_text.length > 0) {
    return body.output_text;
  }
  for (const item of body.output ?? []) {
    for (const part of item.content ?? []) {
      if (typeof part.text === "string" && part.text.length > 0) return part.text;
    }
  }
  return undefined;
}
