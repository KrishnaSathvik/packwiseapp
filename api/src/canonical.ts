import {
  canonicalItemIDs,
  reasonCodes,
  requiredReasonArguments,
  vocabulary,
} from "./generated.ts";
import type { ReasonArgumentPair } from "./types.ts";

/**
 * Domain validation: the layer that decides what the model is allowed to have
 * said. Schema validation proves the shape; this proves the content.
 *
 * Nothing here throws on a bad element. One invented item ID should cost that
 * suggestion, not the whole response — the rejection count is logged so a model
 * that starts inventing is visible.
 */

export type Filtered<T> = {
  kept: T[];
  rejected: { reason: string; count: number }[];
};

function tally(rejections: string[]): { reason: string; count: number }[] {
  const counts = new Map<string, number>();
  for (const reason of rejections) counts.set(reason, (counts.get(reason) ?? 0) + 1);
  return [...counts].map(([reason, count]) => ({ reason, count }));
}

export function isKnownItem(id: string): boolean {
  return canonicalItemIDs().has(id);
}

export function isKnownReasonCode(code: string): boolean {
  return reasonCodes().has(code);
}

export function toArgumentMap(pairs: ReasonArgumentPair[]): Record<string, string> {
  const map: Record<string, string> = {};
  for (const pair of pairs) map[pair.name] = pair.value;
  return map;
}

/** Confidence is internal. Out-of-range values are dropped, not clamped silently into meaning. */
export function normalizeConfidence(value: number): number | undefined {
  if (!Number.isFinite(value) || value < 0 || value > 1) return undefined;
  return value;
}

type ItemBearing = {
  canonicalItemID: string;
  reasonCode: string;
  reasonArguments?: ReasonArgumentPair[];
};

/**
 * A reason code names a localized template; the arguments fill its
 * placeholders. Supplying the wrong ones renders literal braces to the
 * customer, so a candidate that cannot render is dropped like any other
 * domain-invalid one.
 */
export function canRenderReason(candidate: ItemBearing): boolean {
  const supplied = new Set((candidate.reasonArguments ?? []).map((pair) => pair.name));
  return requiredReasonArguments(candidate.reasonCode).every((name) => supplied.has(name));
}

/**
 * Applies the rules the engine owns: the item must exist in the catalog, the
 * reason code must resolve to a known template, and the model may not propose
 * something the list already has.
 */
export function filterCandidates<T extends ItemBearing>(
  candidates: T[],
  options: { presentItemIDs?: Iterable<string>; requirePresent?: boolean } = {},
): Filtered<T> {
  const present = new Set(options.presentItemIDs ?? []);
  const seen = new Set<string>();
  const kept: T[] = [];
  const rejections: string[] = [];

  for (const candidate of candidates) {
    if (!isKnownItem(candidate.canonicalItemID)) {
      rejections.push("unknown_canonical_item");
      continue;
    }
    if (!isKnownReasonCode(candidate.reasonCode)) {
      rejections.push("unknown_reason_code");
      continue;
    }
    if (!canRenderReason(candidate)) {
      rejections.push("unrenderable_reason");
      continue;
    }
    if (options.requirePresent === true && !present.has(candidate.canonicalItemID)) {
      rejections.push("not_on_list");
      continue;
    }
    if (options.requirePresent !== true && present.has(candidate.canonicalItemID)) {
      rejections.push("already_on_list");
      continue;
    }
    if (seen.has(candidate.canonicalItemID)) {
      rejections.push("duplicate");
      continue;
    }
    seen.add(candidate.canonicalItemID);
    kept.push(candidate);
  }

  return { kept, rejected: tally(rejections) };
}

/** Chips and activities are closed vocabularies shared with the iOS enums. */
export function filterVocabulary(
  values: string[],
  kind: "chips" | "activities",
): Filtered<string> {
  const allowed = new Set(vocabulary()[kind]);
  const kept: string[] = [];
  const rejections: string[] = [];
  for (const value of values) {
    if (!allowed.has(value)) {
      rejections.push(`unknown_${kind}`);
      continue;
    }
    if (kept.includes(value)) continue;
    kept.push(value);
  }
  return { kept, rejected: tally(rejections) };
}
