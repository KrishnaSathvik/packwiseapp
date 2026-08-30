import { ProviderError, providerErrorForStatus } from "../errors.ts";

/**
 * The HTTP boundary, kept separate from the adapter so tests can inspect the
 * exact outbound request without a key or a network.
 */

export type OpenAIRequestBody = {
  model: string;
  input: { role: "system" | "user"; content: string }[];
  text: {
    format: {
      type: "json_schema";
      name: string;
      strict: true;
      schema: object;
    };
  };
  store: false;
  safety_identifier: string;
};

export type OpenAIResponseBody = {
  id?: string;
  output_text?: string;
  output?: {
    content?: { type?: string; text?: string }[];
  }[];
  usage?: { input_tokens?: number; output_tokens?: number };
};

export interface OpenAITransport {
  send(options: {
    body: OpenAIRequestBody;
    apiKey: string;
    baseURL: string;
    requestID: string;
    signal: AbortSignal;
  }): Promise<OpenAIResponseBody>;
}

export class FetchOpenAITransport implements OpenAITransport {
  async send(options: {
    body: OpenAIRequestBody;
    apiKey: string;
    baseURL: string;
    requestID: string;
    signal: AbortSignal;
  }): Promise<OpenAIResponseBody> {
    let response: Response;
    try {
      response = await fetch(`${options.baseURL}/responses`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${options.apiKey}`,
          "X-Request-ID": options.requestID,
        },
        body: JSON.stringify(options.body),
        signal: options.signal,
      });
    } catch (error) {
      const aborted = options.signal.aborted || (error as { name?: string }).name === "AbortError";
      throw new ProviderError(aborted ? "timeout" : "network");
    }

    if (!response.ok) {
      const retryAfter = Number(response.headers.get("retry-after"));
      throw providerErrorForStatus(
        response.status,
        Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter : undefined,
      );
    }

    try {
      return (await response.json()) as OpenAIResponseBody;
    } catch {
      throw new ProviderError("malformed", { message: "response body was not JSON" });
    }
  }
}
