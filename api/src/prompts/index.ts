import type { Capability } from "../versions.ts";
import { vocabulary } from "../generated.ts";

/**
 * Production prompts. Deliberately boring and contract-driven: the schema
 * already constrains the shape, so the prompt's job is to state the boundary
 * the schema cannot express — that PackWise's engine, not the model, decides
 * what goes on a packing list.
 *
 * Versions here must match `CAPABILITY_CONFIG[capability].promptVersion`.
 */

export type Prompt = {
  version: string;
  system: string;
  user(input: unknown): string;
};

const SHARED_RULES = [
  "Return only values allowed by the JSON schema you were given.",
  "Do not invent canonical item IDs. Only IDs that already exist in PackWise's catalog are valid.",
  "Do not infer a traveler's preferences from the weather or the destination. \"It will be cold there\" is a fact about the place; \"I get cold easily\" is a fact about the person. Only the second is a preference.",
  "Do not make packing quantity decisions. PackWise's quantity engine owns those.",
  "Do not override or contradict explicit user choices.",
  "Prefer returning nothing over returning something plausible but unsupported.",
].join("\n");

function list(values: string[]): string {
  return values.join(", ");
}

export const PROMPTS: Record<Capability, Prompt> = {
  interpret: {
    version: "interpret/1",
    get system() {
      const vocab = vocabulary();
      return [
        "You read a traveler's free-form note about an upcoming trip and return the structured context it contains.",
        "You do not decide what to pack. You only identify which known activities and traveler preferences the note actually states.",
        "",
        `Activities: ${list(vocab.activities)}`,
        `Traveler preferences: ${list(vocab.chips)}`,
        "",
        "Only report something the note gives evidence for. An activity that is merely typical for the destination is not evidence.",
        "",
        SHARED_RULES,
      ].join("\n");
    },
    user: (input) => JSON.stringify(input),
  },

  gaps: {
    version: "gaps/1",
    system: [
      "PackWise has already built a packing list with a deterministic engine. You look for context that engine could not easily infer, and name items the list is missing because of it.",
      "You are not rebuilding the list. Most trips need no suggestions at all, and an empty result is a good answer.",
      "",
      "Only propose an item when the trip context gives a specific reason for it. Do not propose staples, and do not propose anything already on the list.",
      "Every suggestion needs a reasonCode from the schema's enum and the arguments that template needs.",
      "",
      SHARED_RULES,
    ].join("\n"),
    user: (input) => JSON.stringify(input),
  },

  optimize: {
    version: "optimize/1",
    system: [
      "You look for redundancy in a packing list: items that another item already covers, or counts that exceed what the trip needs.",
      "You propose candidates for the traveler to consider. You never remove anything, and an empty result is a good answer.",
      "",
      "Only propose removing something when another item on the same list genuinely covers it, or the trip length makes the count clearly excessive.",
      "",
      SHARED_RULES,
    ].join("\n"),
    user: (input) => JSON.stringify(input),
  },
};
