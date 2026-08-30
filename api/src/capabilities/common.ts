import type { ModelTripShape } from "../model/inputs.ts";
import type { PackingItemDTO, TripContextDTO } from "../types.ts";

const MS_PER_DAY = 86_400_000;

export function durationDays(context: TripContextDTO): number {
  if (context.durationDays && context.durationDays > 0) return context.durationDays;
  const start = Date.parse(context.startDate);
  const end = Date.parse(context.endDate);
  if (Number.isNaN(start) || Number.isNaN(end)) return 1;
  return Math.max(1, Math.round((end - start) / MS_PER_DAY) + 1);
}

/**
 * The minimised shape sent to the model. Free-form user notes are deliberately
 * absent: only /v1/trip/interpret sends note text, and only because that is the
 * capability's whole input.
 */
export function tripShape(context: TripContextDTO): ModelTripShape {
  return {
    destination: context.destination.displayName,
    countryCode: context.destination.countryCode,
    tripType: context.tripType,
    durationDays: durationDays(context),
    activities: [...context.activities],
    contextChips: [...(context.contextChips ?? [])],
    bagType: context.bagType,
    packingStyle: context.packingStyle,
    travelerCount: context.travelerCount ?? 1,
    ...(context.weatherSummary ? { weatherSummary: context.weatherSummary } : {}),
  };
}

export function presentItemIDs(context: TripContextDTO, items: PackingItemDTO[]): string[] {
  const ids = new Set<string>(context.currentItemIDs ?? []);
  for (const item of items) {
    if (item.canonicalItemID) ids.add(item.canonicalItemID);
  }
  return [...ids];
}
