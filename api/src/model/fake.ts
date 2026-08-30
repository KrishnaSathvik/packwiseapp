import type { ModelAdapter, ModelRequest, ModelResult } from "./adapter.ts";
import type { GapsInput, InterpretInput, ModelTripShape, OptimizeInput } from "./inputs.ts";
import type {
  ModelGapSuggestion,
  ModelOptimization,
  ModelPackingGaps,
  ModelPackingOptimizations,
  ModelTripInterpretation,
} from "../types.ts";

/**
 * Deterministic stand-in for the model. It exists so the whole pipeline —
 * request validation, canonical validation, response validation, iOS decoding —
 * can be proved without an API key and without mixing infrastructure bugs with
 * model-behaviour bugs. Its output is contract-valid, not clever.
 *
 * The eval fixtures in shared/fixtures/trips run against this adapter, which
 * gives M3A-2 a green baseline to compare the real model against.
 */

type Pattern = { value: string; phrases: string[] };

const ACTIVITY_PATTERNS: Pattern[] = [
  { value: "hiking", phrases: ["hik", "trail", "trek"] },
  { value: "photography", phrases: ["photograph", "photo ", "camera", "shooting"] },
  { value: "yoga", phrases: ["yoga"] },
  { value: "snorkeling", phrases: ["snorkel"] },
  { value: "running", phrases: ["running", "go for a run", "morning run", "jog"] },
  { value: "museums", phrases: ["museum", "gallery", "exhibit"] },
  { value: "work", phrases: ["meeting", "client", "conference", "office", "presentation"] },
  { value: "wildlife", phrases: ["wildlife", "safari", "birding"] },
  { value: "boatTrip", phrases: ["boat", "sailing", "ferry", "cruise"] },
  { value: "swimming", phrases: ["swim", "pool", "ocean"] },
  { value: "beachDays", phrases: ["beach"] },
  { value: "shopping", phrases: ["shopping"] },
  { value: "nightlife", phrases: ["nightlife", "bars", "clubbing", "night out"] },
  // "fancy dinner", "fine dining", and "dinner" all land on niceDinner: the
  // packing signal is needing a nicer outfit, not the restaurant's tier.
  {
    value: "niceDinner",
    phrases: ["fancy dinner", "fine dining", "nice restaurant", "upscale dinner", "tasting menu", "nice meal", "dinner"],
  },
  { value: "walking", phrases: ["walking", "walk a lot", "on our feet", "on foot", "theme park"] },
  { value: "sightseeing", phrases: ["sightsee", "landmark", "tourist", "explore"] },
];

const CHIP_PATTERNS: Pattern[] = [
  // Phrase-anchored on purpose: "it will be cold" is a forecast, not a preference.
  { value: "getColdEasily", phrases: ["get cold easily", "gets cold easily", "i get cold", "run cold", "always cold"] },
  { value: "usuallyWorkOut", phrases: ["work out", "workout", "gym", "exercise"] },
  { value: "runWhileTraveling", phrases: ["go for a run", "run while", "morning run"] },
  { value: "bringingLaptop", phrases: ["laptop", "macbook"] },
  { value: "needFormalOutfit", phrases: ["formal", "wedding", "black tie", "look sharp", "a suit"] },
  { value: "dailyMedication", phrases: ["medication", "prescription", "my meds"] },
  { value: "wearContacts", phrases: ["contacts", "contact lens"] },
  { value: "laundryAvailable", phrases: ["laundry", "washer", "washing machine", "laundromat"] },
  {
    value: "travelingInternationally",
    phrases: ["abroad", "overseas", "international", "in asia", "in europe", "in africa", "south america"],
  },
];

function matches(note: string, patterns: Pattern[]): string[] {
  const found: string[] = [];
  for (const pattern of patterns) {
    if (pattern.phrases.some((phrase) => note.includes(phrase)) && !found.includes(pattern.value)) {
      found.push(pattern.value);
    }
  }
  return found;
}

function interpret(input: InterpretInput): ModelTripInterpretation {
  const note = input.note.toLowerCase();
  return {
    inferredActivities: matches(note, ACTIVITY_PATTERNS),
    inferredChips: matches(note, CHIP_PATTERNS),
    noteSummary: null,
  };
}

function pairs(record: Record<string, string>): { name: string; value: string }[] {
  return Object.entries(record).map(([name, value]) => ({ name, value }));
}

function firstOf(trip: ModelTripShape, candidates: string[]): string | undefined {
  return candidates.find((candidate) => trip.activities.includes(candidate));
}

function gaps(input: GapsInput): ModelPackingGaps {
  const { trip } = input;
  const present = new Set(input.presentItemIDs);
  const suggestions: ModelGapSuggestion[] = [];

  const add = (
    canonicalItemID: string,
    reasonCode: string,
    reasonArguments: Record<string, string>,
    confidence: number,
    signals: string[],
  ) => {
    if (present.has(canonicalItemID)) return;
    suggestions.push({
      canonicalItemID,
      reasonCode,
      reasonArguments: pairs(reasonArguments),
      reason: null,
      confidence,
      signals,
    });
  };

  const onFoot = firstOf(trip, ["walking", "sightseeing", "photography", "museums"]);
  if (onFoot && trip.durationDays >= 3) {
    add("electronics.power_bank", "context.gap_activity", { activity: onFoot }, 0.82, ["activity", "duration"]);
  }
  if (trip.activities.includes("hiking") && trip.durationDays >= 3) {
    add("health.blister_pads", "context.gap_activity", { activity: "hiking" }, 0.74, ["activity"]);
  }
  const inWater = firstOf(trip, ["beachDays", "swimming"]);
  if (inWater) {
    add("toiletries.aloe", "context.gap_activity", { activity: inWater }, 0.68, ["activity", "weather"]);
  }
  if (trip.tripType === "weddingEvent") {
    add("miscellaneous.wedding_card", "context.gap_trip_type", { tripType: trip.tripType }, 0.7, ["tripType"]);
  }
  if (trip.durationDays >= 7 && trip.contextChips.includes("travelingInternationally")) {
    add(
      "travel_comfort.neck_pillow",
      "context.gap_duration",
      { tripDays: String(trip.durationDays) },
      0.66,
      ["duration", "destination"],
    );
  }

  return { suggestions };
}

const SPACE_CONSTRAINED = new Set(["personalItem", "carryOn", "backpack"]);

function optimize(input: OptimizeInput): ModelPackingOptimizations {
  const { trip } = input;
  const quantities = new Map(input.items.map((item) => [item.canonicalItemID, item.quantity]));
  const optimizations: ModelOptimization[] = [];

  if (
    SPACE_CONSTRAINED.has(trip.bagType) &&
    quantities.has("footwear.running_shoes") &&
    quantities.has("footwear.walking_shoes")
  ) {
    optimizations.push({
      canonicalItemID: "footwear.walking_shoes",
      reasonCode: "context.optimize_duplicate",
      reasonArguments: pairs({ otherItem: "footwear.running_shoes" }),
      reason: null,
      suggestedQuantity: null,
      confidence: 0.61,
    });
  }

  if (trip.packingStyle === "light") {
    for (const item of input.items) {
      if (item.quantity > trip.durationDays) {
        optimizations.push({
          canonicalItemID: item.canonicalItemID,
          reasonCode: "context.optimize_quantity",
          reasonArguments: pairs({
            quantity: String(trip.durationDays),
            tripDays: String(trip.durationDays),
          }),
          reason: null,
          suggestedQuantity: trip.durationDays,
          confidence: 0.58,
        });
      }
    }
  }

  return { optimizations };
}

export class FakeModelAdapter implements ModelAdapter {
  readonly name = "fake";

  async produce(request: ModelRequest): Promise<ModelResult> {
    request.signal.throwIfAborted();
    return { output: this.output(request), providerResponseID: `fake-${request.requestID}` };
  }

  private output(request: ModelRequest): unknown {
    switch (request.capability) {
      case "interpret":
        return interpret(request.input as InterpretInput);
      case "gaps":
        return gaps(request.input as GapsInput);
      case "optimize":
        return optimize(request.input as OptimizeInput);
    }
  }
}
